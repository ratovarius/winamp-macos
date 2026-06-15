import MetalKit
import SwiftUI

final class MetalVisualizationRenderer: NSObject, MTKViewDelegate {
    private let featureBus: AudioFeatureBus
    private var plugin: MetalVisualizationPlugin
    private let pipelineProvider: MetalPipelineProvider
    private var featureSmoother = VisualizationFeatureSmoother()
    private var startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    var device: MTLDevice {
        self.pipelineProvider.device
    }

    init(
        featureBus: AudioFeatureBus = .shared,
        plugin: MetalVisualizationPlugin,
        pipelineProvider: MetalPipelineProvider = MetalPipelineProvider()
    ) {
        self.featureBus = featureBus
        self.plugin = plugin
        self.pipelineProvider = pipelineProvider
        super.init()
    }

    func updatePlugin(_ plugin: MetalVisualizationPlugin) {
        self.plugin = plugin
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = pipelineProvider.commandQueue.makeCommandBuffer()
        else {
            return
        }

        let now = CACurrentMediaTime()
        let deltaTime = Float(now - self.lastFrameTime)
        self.lastFrameTime = now

        let raw = self.featureBus.snapshot()
        let smoothedSpectrum = self.featureSmoother.update(
            targets: raw.spectrum,
            isPlaying: raw.isPlaying,
            deltaTime: deltaTime
        )

        let features = AudioFeatures(
            spectrum: smoothedSpectrum,
            waveformLeft: raw.waveformLeft,
            waveformRight: raw.waveformRight,
            isPlaying: raw.isPlaying
        )

        let elapsed = now - self.startTime

        if case .miniSpectrum = self.plugin.kind {
            self.drawSpectrumWithPeakPersistence(
                commandBuffer: commandBuffer,
                drawable: drawable,
                view: view,
                features: features,
                time: elapsed,
                deltaTime: deltaTime
            )
        } else {
            guard let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else {
                return
            }

            self.plugin.draw(
                encoder: encoder,
                features: features,
                time: elapsed,
                drawableSize: view.drawableSize,
                pipelines: self.pipelineProvider
            )
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawSpectrumWithPeakPersistence(
        commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable,
        view: MTKView,
        features: AudioFeatures,
        time: CFTimeInterval,
        deltaTime: Float
    ) {
        let width = max(Int(view.drawableSize.width), 1)
        let height = max(Int(view.drawableSize.height), 1)
        self.pipelineProvider.ensureOffscreenTextures(width: width, height: height)

        guard let scratch = self.pipelineProvider.scratchTexture,
              let history = self.pipelineProvider.historyTexture,
              let composite = self.pipelineProvider.compositeTexture,
              let compositePipeline = self.pipelineProvider.spectrumCompositePipeline
        else {
            return
        }

        let barsPass = MTLRenderPassDescriptor()
        barsPass.colorAttachments[0].texture = scratch
        barsPass.colorAttachments[0].loadAction = .clear
        barsPass.colorAttachments[0].storeAction = .store
        barsPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let barsEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: barsPass) else { return }
        self.plugin.draw(
            encoder: barsEncoder,
            features: features,
            time: time,
            drawableSize: view.drawableSize,
            pipelines: self.pipelineProvider
        )
        barsEncoder.endEncoding()

        let compositePass = MTLRenderPassDescriptor()
        compositePass.colorAttachments[0].texture = composite
        compositePass.colorAttachments[0].loadAction = .clear
        compositePass.colorAttachments[0].storeAction = .store
        compositePass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositePass) else { return }
        compositeEncoder.setRenderPipelineState(compositePipeline)
        compositeEncoder.setFragmentTexture(scratch, index: 0)
        compositeEncoder.setFragmentTexture(history, index: 1)
        var historyDecay = pow(0.91, deltaTime * 60)
        compositeEncoder.setFragmentBytes(&historyDecay, length: MemoryLayout<Float>.stride, index: 0)
        compositeEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        compositeEncoder.endEncoding()

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        blitEncoder.copy(
            from: composite,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: drawable.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.copy(
            from: composite,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: history,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
    }
}

private enum MetalVisualizationViewFactory {
    static func configure(_ view: MTKView, device: MTLDevice, delegate: MTKViewDelegate) {
        view.device = device
        view.delegate = delegate
        view.preferredFramesPerSecond = VisualizationDisplayTiming.preferredFramesPerSecond()
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.layer?.isOpaque = true
    }
}

struct MetalVisualizationView: NSViewRepresentable {
    let visualizationMode: VisualizationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: self.visualizationMode)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        MetalVisualizationViewFactory.configure(
            view,
            device: context.coordinator.renderer.device,
            delegate: context.coordinator.renderer
        )
        return view
    }

    func updateNSView(_: MTKView, context: Context) {
        context.coordinator.setMode(self.visualizationMode)
    }

    @MainActor
    final class Coordinator {
        let renderer: MetalVisualizationRenderer
        private let spectrumPlugin = MiniSpectrumMetalPlugin()
        private let oscilloscopePlugin = MiniOscilloscopeMetalPlugin()

        init(mode: VisualizationMode) {
            self.renderer = MetalVisualizationRenderer(
                plugin: Self.plugin(for: mode, spectrum: spectrumPlugin, oscilloscope: oscilloscopePlugin)
            )
        }

        func setMode(_ mode: VisualizationMode) {
            self.renderer.updatePlugin(
                Self.plugin(for: mode, spectrum: self.spectrumPlugin, oscilloscope: self.oscilloscopePlugin)
            )
        }

        private static func plugin(
            for mode: VisualizationMode,
            spectrum: MiniSpectrumMetalPlugin,
            oscilloscope: MiniOscilloscopeMetalPlugin
        ) -> MetalVisualizationPlugin {
            switch mode {
            case .bars:
                spectrum
            case .oscilloscope:
                oscilloscope
            }
        }
    }
}

struct MilkdropMetalVisualizationView: NSViewRepresentable {
    let preset: VisualizationPreset

    func makeCoordinator() -> Coordinator {
        Coordinator(preset: self.preset)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        MetalVisualizationViewFactory.configure(
            view,
            device: context.coordinator.renderer.device,
            delegate: context.coordinator.renderer
        )
        return view
    }

    func updateNSView(_: MTKView, context: Context) {
        context.coordinator.updatePreset(self.preset)
    }

    @MainActor
    final class Coordinator {
        let renderer: MetalVisualizationRenderer
        private let plugin: FullscreenMetalPlugin

        init(preset: VisualizationPreset) {
            let plugin = FullscreenMetalPlugin(preset: preset)
            self.plugin = plugin
            self.renderer = MetalVisualizationRenderer(plugin: plugin)
        }

        func updatePreset(_ preset: VisualizationPreset) {
            self.plugin.preset = preset
        }
    }
}

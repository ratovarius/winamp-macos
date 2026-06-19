import MetalKit
import SwiftUI

@MainActor
final class MetalVisualizationRenderer: NSObject, MTKViewDelegate {
    private let featureBus: AudioFeatureBus
    private var plugin: MetalVisualizationPlugin
    private let pipelineProvider: MetalPipelineProvider
    private var featureSmoother = VisualizationFeatureSmoother()
    private var peakTracker = SpectrumPeakTracker()
    private var frameClock: RenderFrameClock
    private var idleGate = VisualizerIdleGate()
    private let inFlightSemaphore = DispatchSemaphore(
        value: MetalPipelineProvider.maxBuffersInFlight)

    /// Energy below this (on the 0…1 smoothed bars) counts as visually silent.
    private static let idleActivityThreshold: Float = 0.002

    var device: MTLDevice {
        self.pipelineProvider.device
    }

    /// Only the audio-reactive mini visualizers go static when idle. The fullscreen
    /// Milkdrop plugin animates continuously, so it must never idle-pause.
    private var isMiniKind: Bool {
        switch self.plugin.kind {
        case .miniSpectrum, .miniAnalyzer, .miniOscilloscope: true
        case .fullscreen: false
        }
    }

    /// Resumes the display loop after an idle pause (called when playback restarts).
    func resume(_ view: MTKView) {
        self.idleGate.wake()
        self.frameClock.resetDelta()
        view.isPaused = false
    }

    init(
        featureBus: AudioFeatureBus = .shared,
        plugin: MetalVisualizationPlugin,
        pipelineProvider: MetalPipelineProvider = MetalPipelineProvider(),
        clock: VisualizationClock = MediaTimeClock()
    ) {
        self.featureBus = featureBus
        self.plugin = plugin
        self.pipelineProvider = pipelineProvider
        self.frameClock = RenderFrameClock(clock: clock)
        super.init()
    }

    func updatePlugin(_ plugin: MetalVisualizationPlugin) {
        guard type(of: plugin) != type(of: self.plugin) else { return }
        self.plugin = plugin
        self.resetTransientState()
    }

    private func resetTransientState() {
        self.featureSmoother = VisualizationFeatureSmoother()
        self.peakTracker.reset()
        self.idleGate.wake()
        self.pipelineProvider.clearHistoryTexture()
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        // Triple-buffer back-pressure: block until the GPU finishes a frame so we never overwrite
        // a buffer the GPU is still reading. The matching signal fires in the completion handler.
        self.inFlightSemaphore.wait()

        // Per-frame CPU encoding cost: visible in Instruments' os_signpost track. Started
        // after the back-pressure wait so the interval reflects encoding work, not GPU stalls.
        let frameSignpost = Instrumentation.visualization.beginInterval("frame")
        defer { Instrumentation.visualization.endInterval("frame", frameSignpost) }

        guard let commandBuffer = pipelineProvider.commandQueue.makeCommandBuffer() else {
            self.inFlightSemaphore.signal()
            return
        }

        let semaphore = self.inFlightSemaphore
        commandBuffer.addCompletedHandler { buffer in
            semaphore.signal()
            // GPU execution time for this frame, emitted as a signpost event so it can be
            // graphed in Instruments alongside the CPU "frame" interval.
            let gpuMicroseconds = Int((buffer.gpuEndTime - buffer.gpuStartTime) * 1_000_000)
            Instrumentation.visualization.emitEvent("gpu", "gpu_us=\(gpuMicroseconds)")
        }

        guard let drawable = view.currentDrawable else {
            // Commit so the completion handler runs and balances the semaphore.
            commandBuffer.commit()
            return
        }

        // Rotate to this frame's buffer slot before any plugin writes into the rings.
        self.pipelineProvider.advanceFrame()

        let (now, elapsed, rawDelta) = self.frameClock.tick()
        let deltaTime = Float(rawDelta)

        let waveformSampleCount: Int
        if case .miniOscilloscope = self.plugin.kind {
            waveformSampleCount = AudioFeatures.scopeWaveformSampleCount
        } else {
            waveformSampleCount = AudioFeatures.waveformSampleCount
        }

        let raw = self.featureBus.snapshot(at: now, waveformSampleCount: waveformSampleCount)
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

        // Idle detection: a mini visualizer is "active" while playing or while the
        // smoothed bars still carry visible energy (release tails). Once both are quiet
        // for the gate's hold window, pause after this frame so the loop stops redrawing
        // a static image. `resume(_:)` (driven by playback state) wakes it back up.
        let peakEnergy = smoothedSpectrum.max() ?? 0
        let isActive = raw.isPlaying || peakEnergy > Self.idleActivityThreshold
        let shouldPause = self.isMiniKind
            && self.idleGate.update(isActive: isActive, deltaTime: CFTimeInterval(deltaTime))

        if case .miniSpectrum = self.plugin.kind {
            self.drawSpectrumWithPeakPersistence(
                commandBuffer: commandBuffer,
                drawable: drawable,
                view: view,
                features: features,
                time: elapsed,
                deltaTime: deltaTime
            )
        } else if case .miniAnalyzer = self.plugin.kind {
            let peakResult = self.peakTracker.update(
                targets: smoothedSpectrum,
                isPlaying: raw.isPlaying,
                deltaTime: deltaTime
            )
            let analyzerFeatures = AudioFeatures(
                spectrum: peakResult.bars,
                waveformLeft: raw.waveformLeft,
                waveformRight: raw.waveformRight,
                isPlaying: raw.isPlaying
            )
            self.drawAnalyzer(
                commandBuffer: commandBuffer,
                view: view,
                features: analyzerFeatures,
                peaks: peakResult.peaks,
                time: elapsed
            )
        } else {
            if let renderPassDescriptor = view.currentRenderPassDescriptor,
                let encoder = commandBuffer.makeRenderCommandEncoder(
                    descriptor: renderPassDescriptor)
            {
                self.plugin.draw(
                    encoder: encoder,
                    features: features,
                    time: elapsed,
                    drawableSize: view.drawableSize,
                    pipelines: self.pipelineProvider
                )
                encoder.endEncoding()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Freeze the loop after presenting the final (already-decayed) frame. Resumed via
        // `resume(_:)` when playback restarts.
        if shouldPause {
            view.isPaused = true
        }
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

        guard let barsEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: barsPass) else {
            return
        }
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
        compositePass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositePass)
        else { return }
        compositeEncoder.setRenderPipelineState(compositePipeline)
        compositeEncoder.setFragmentTexture(scratch, index: 0)
        compositeEncoder.setFragmentTexture(history, index: 1)
        var historyDecay = pow(0.91, deltaTime * 60)
        compositeEncoder.setFragmentBytes(
            &historyDecay, length: MemoryLayout<Float>.stride, index: 0)
        compositeEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        compositeEncoder.endEncoding()

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
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

        // Present the composite into the drawable with a render pass. The drawable is
        // `framebufferOnly` (the optimal config), which forbids using it as a blit destination,
        // so present via a fullscreen copy draw instead of a blit.
        let presentPass = MTLRenderPassDescriptor()
        presentPass.colorAttachments[0].texture = drawable.texture
        presentPass.colorAttachments[0].loadAction = .dontCare
        presentPass.colorAttachments[0].storeAction = .store

        guard let copyPipeline = self.pipelineProvider.copyPipeline,
            let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass)
        else {
            return
        }
        presentEncoder.setRenderPipelineState(copyPipeline)
        presentEncoder.setFragmentTexture(composite, index: 0)
        presentEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        presentEncoder.endEncoding()
    }

    private func drawAnalyzer(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: AudioFeatures,
        peaks: [Float],
        time: CFTimeInterval
    ) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
            let analyzer = self.plugin as? MiniAnalyzerMetalPlugin
        else {
            return
        }

        analyzer.draw(
            encoder: encoder,
            features: features,
            peaks: peaks,
            time: time,
            drawableSize: view.drawableSize,
            pipelines: self.pipelineProvider
        )
        encoder.endEncoding()
    }
}

@MainActor
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
    let isPlaying: Bool

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

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.setMode(self.visualizationMode)
        // Playback (re)started: wake the loop. The renderer self-pauses again once the
        // visualizer has gone idle (see `VisualizerIdleGate`).
        if self.isPlaying {
            context.coordinator.renderer.resume(view)
        }
    }

    @MainActor
    final class Coordinator {
        let renderer: MetalVisualizationRenderer
        private let spectrumPlugin: MiniSpectrumMetalPlugin
        private let analyzerPlugin: MiniAnalyzerMetalPlugin
        private let oscilloscopePlugin: MiniOscilloscopeMetalPlugin
        private var currentMode: VisualizationMode

        init(mode: VisualizationMode) {
            let spectrum = MiniSpectrumMetalPlugin()
            let analyzer = MiniAnalyzerMetalPlugin()
            let oscilloscope = MiniOscilloscopeMetalPlugin()
            self.spectrumPlugin = spectrum
            self.analyzerPlugin = analyzer
            self.oscilloscopePlugin = oscilloscope
            self.currentMode = mode
            self.renderer = MetalVisualizationRenderer(
                plugin: Self.plugin(
                    for: mode,
                    spectrum: spectrum,
                    analyzer: analyzer,
                    oscilloscope: oscilloscope
                )
            )
        }

        func setMode(_ mode: VisualizationMode) {
            guard mode != self.currentMode else { return }
            self.currentMode = mode
            self.renderer.updatePlugin(
                Self.plugin(
                    for: mode,
                    spectrum: self.spectrumPlugin,
                    analyzer: self.analyzerPlugin,
                    oscilloscope: self.oscilloscopePlugin
                )
            )
        }

        private static func plugin(
            for mode: VisualizationMode,
            spectrum: MiniSpectrumMetalPlugin,
            analyzer: MiniAnalyzerMetalPlugin,
            oscilloscope: MiniOscilloscopeMetalPlugin
        ) -> MetalVisualizationPlugin {
            switch mode {
            case .bars:
                spectrum
            case .oscilloscope:
                oscilloscope
            case .analyzer:
                analyzer
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

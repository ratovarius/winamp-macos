import Metal
import simd

struct VizUniforms {
    var time: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var resolution: SIMD2<Float>
    var mode: UInt32
    var preset: UInt32
    var energy: Float
    var spectrumBandCount: UInt32
    var scopeSampleCount: UInt32
}

enum MetalVisualizationKind {
    case miniSpectrum
    case miniOscilloscope
    case fullscreen(preset: VisualizationPreset)
}

protocol MetalVisualizationPlugin: AnyObject {
    var kind: MetalVisualizationKind { get }
    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    )
}

/// Per-view Metal buffers and offscreen textures. Pipeline states come from `MetalVisualizationEngine.shared`.
final class MetalPipelineProvider {
    private let engine: MetalVisualizationEngine
    private var spectrumBuffer: MTLBuffer?
    private var waveformLeftBuffer: MTLBuffer?
    private var waveformRightBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    private(set) var scratchTexture: MTLTexture?
    private(set) var historyTexture: MTLTexture?
    private(set) var compositeTexture: MTLTexture?
    private var offscreenWidth = 0
    private var offscreenHeight = 0

    var device: MTLDevice { self.engine.device }
    var commandQueue: MTLCommandQueue { self.engine.commandQueue }
    var spectrumPipeline: MTLRenderPipelineState? { self.engine.spectrumPipeline }
    var spectrumCompositePipeline: MTLRenderPipelineState? { self.engine.spectrumCompositePipeline }
    var oscilloscopePipeline: MTLRenderPipelineState? { self.engine.oscilloscopePipeline }
    var fullscreenPipeline: MTLRenderPipelineState? { self.engine.fullscreenPipeline }

    init(engine: MetalVisualizationEngine = .shared) {
        self.engine = engine
    }

    func ensureOffscreenTextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        guard width != self.offscreenWidth || height != self.offscreenHeight else { return }

        self.offscreenWidth = width
        self.offscreenHeight = height
        self.scratchTexture = self.engine.makeOffscreenTexture(width: width, height: height)
        self.historyTexture = self.engine.makeOffscreenTexture(width: width, height: height)
        self.compositeTexture = self.engine.makeOffscreenTexture(width: width, height: height)
    }

    func updateSpectrumBuffer(_ spectrum: [Float]) -> MTLBuffer? {
        let byteCount = MemoryLayout<Float>.stride * spectrum.count
        if self.spectrumBuffer == nil || self.spectrumBuffer?.length ?? 0 < byteCount {
            self.spectrumBuffer = self.device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        guard let buffer = self.spectrumBuffer else { return nil }
        spectrum.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            memcpy(buffer.contents(), baseAddress, byteCount)
        }
        return buffer
    }

    func updateWaveformBuffer(_ samples: [Float], channel: WaveformChannel) -> MTLBuffer? {
        let byteCount = MemoryLayout<Float>.stride * samples.count
        switch channel {
        case .left:
            if self.waveformLeftBuffer == nil || self.waveformLeftBuffer?.length ?? 0 < byteCount {
                self.waveformLeftBuffer = self.device.makeBuffer(length: byteCount, options: .storageModeShared)
            }
            guard let buffer = self.waveformLeftBuffer else { return nil }
            samples.withUnsafeBytes { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                memcpy(buffer.contents(), baseAddress, byteCount)
            }
            return buffer
        case .right:
            if self.waveformRightBuffer == nil || self.waveformRightBuffer?.length ?? 0 < byteCount {
                self.waveformRightBuffer = self.device.makeBuffer(length: byteCount, options: .storageModeShared)
            }
            guard let buffer = self.waveformRightBuffer else { return nil }
            samples.withUnsafeBytes { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                memcpy(buffer.contents(), baseAddress, byteCount)
            }
            return buffer
        }
    }

    func updateUniformBuffer(_ uniforms: VizUniforms) -> MTLBuffer? {
        let byteCount = MemoryLayout<VizUniforms>.stride
        if self.uniformBuffer == nil {
            self.uniformBuffer = self.device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        guard let buffer = self.uniformBuffer else { return nil }
        var copy = uniforms
        memcpy(buffer.contents(), &copy, byteCount)
        return buffer
    }

    enum WaveformChannel {
        case left
        case right
    }

    func makeSpectrumBuffer(from spectrum: [Float]) -> MTLBuffer? {
        self.updateSpectrumBuffer(spectrum)
    }

    func makeWaveformBuffer(from samples: [Float]) -> MTLBuffer? {
        self.updateWaveformBuffer(samples, channel: .left)
    }

    func makeUniformBuffer(_ uniforms: VizUniforms) -> MTLBuffer? {
        self.updateUniformBuffer(uniforms)
    }
}

final class MiniSpectrumMetalPlugin: MetalVisualizationPlugin {
    let kind: MetalVisualizationKind = .miniSpectrum

    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    ) {
        guard let pipeline = pipelines.spectrumPipeline,
              let spectrumBuffer = pipelines.makeSpectrumBuffer(from: features.spectrum),
              let uniformBuffer = pipelines.makeUniformBuffer(
                  VizUniforms(
                      time: Float(time),
                      bass: features.bassEnergy,
                      mid: features.midEnergy,
                      treble: features.trebleEnergy,
                      resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                      mode: 0,
                      preset: 0,
                      energy: features.overallEnergy,
                      spectrumBandCount: UInt32(AudioFeatures.spectrumBandCount),
                      scopeSampleCount: 0
                  )
              )
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(spectrumBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: AudioFeatures.spectrumBandCount * 6)
    }
}

final class MiniOscilloscopeMetalPlugin: MetalVisualizationPlugin {
    let kind: MetalVisualizationKind = .miniOscilloscope

    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    ) {
        guard let pipeline = pipelines.oscilloscopePipeline,
              let leftBuffer = pipelines.updateWaveformBuffer(features.waveformLeft, channel: .left),
              let rightBuffer = pipelines.updateWaveformBuffer(features.waveformRight, channel: .right),
              let uniformBuffer = pipelines.makeUniformBuffer(
                  VizUniforms(
                      time: Float(time),
                      bass: features.bassEnergy,
                      mid: features.midEnergy,
                      treble: features.trebleEnergy,
                      resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                      mode: 1,
                      preset: 0,
                      energy: features.overallEnergy,
                      spectrumBandCount: 0,
                      scopeSampleCount: UInt32(AudioFeatures.waveformSampleCount)
                  )
              )
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(leftBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(rightBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: AudioFeatures.waveformSampleCount)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: AudioFeatures.waveformSampleCount, vertexCount: AudioFeatures.waveformSampleCount)
    }
}

final class FullscreenMetalPlugin: MetalVisualizationPlugin {
    var preset: VisualizationPreset

    var kind: MetalVisualizationKind {
        .fullscreen(preset: self.preset)
    }

    init(preset: VisualizationPreset) {
        self.preset = preset
    }

    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    ) {
        guard let pipeline = pipelines.fullscreenPipeline,
              let uniformBuffer = pipelines.makeUniformBuffer(
                  VizUniforms(
                      time: Float(time),
                      bass: features.bassEnergy,
                      mid: features.midEnergy,
                      treble: features.trebleEnergy,
                      resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                      mode: 2,
                      preset: UInt32(self.preset.rawValue),
                      energy: features.overallEnergy,
                      spectrumBandCount: 0,
                      scopeSampleCount: 0
                  )
              )
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

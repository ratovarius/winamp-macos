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
    case miniAnalyzer
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
    private var peakBuffer: MTLBuffer?
    private var scopeColumnBuffer: MTLBuffer?
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
    var spectrumPeakPipeline: MTLRenderPipelineState? { self.engine.spectrumPeakPipeline }
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
        self.updateFloatBuffer(&self.spectrumBuffer, values: spectrum)
    }

    func updatePeakBuffer(_ peaks: [Float]) -> MTLBuffer? {
        self.updateFloatBuffer(&self.peakBuffer, values: peaks)
    }

    func updateScopeColumnBuffer(_ columns: [Float]) -> MTLBuffer? {
        self.updateFloatBuffer(&self.scopeColumnBuffer, values: columns)
    }

    private func updateFloatBuffer(_ buffer: inout MTLBuffer?, values: [Float]) -> MTLBuffer? {
        let byteCount = MemoryLayout<Float>.stride * values.count
        if buffer == nil || buffer?.length ?? 0 < byteCount {
            buffer = self.device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        guard let buffer else { return nil }
        values.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            memcpy(buffer.contents(), baseAddress, byteCount)
        }
        return buffer
    }

    func clearHistoryTexture() {
        guard let history = self.historyTexture,
              let commandBuffer = self.commandQueue.makeCommandBuffer()
        else {
            return
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = history
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.endEncoding()
        commandBuffer.commit()
    }

    func updateWaveformBuffer(_ samples: [Float], channel: WaveformChannel) -> MTLBuffer? {
        switch channel {
        case .left:
            self.updateFloatBuffer(&self.waveformLeftBuffer, values: samples)
        case .right:
            self.updateFloatBuffer(&self.waveformRightBuffer, values: samples)
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

final class MiniAnalyzerMetalPlugin: MetalVisualizationPlugin {
    let kind: MetalVisualizationKind = .miniAnalyzer

    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        peaks: [Float],
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    ) {
        let uniforms = VizUniforms(
            time: Float(time),
            bass: features.bassEnergy,
            mid: features.midEnergy,
            treble: features.trebleEnergy,
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            mode: 2,
            preset: 0,
            energy: features.overallEnergy,
            spectrumBandCount: UInt32(AudioFeatures.spectrumBandCount),
            scopeSampleCount: 0
        )

        guard let barPipeline = pipelines.spectrumPipeline,
              let spectrumBuffer = pipelines.makeSpectrumBuffer(from: features.spectrum),
              let uniformBuffer = pipelines.makeUniformBuffer(uniforms)
        else {
            return
        }

        encoder.setRenderPipelineState(barPipeline)
        encoder.setVertexBuffer(spectrumBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: AudioFeatures.spectrumBandCount * 6)

        guard let peakPipeline = pipelines.spectrumPeakPipeline,
              let peakBuffer = pipelines.updatePeakBuffer(peaks)
        else {
            return
        }

        encoder.setRenderPipelineState(peakPipeline)
        encoder.setVertexBuffer(peakBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: AudioFeatures.spectrumBandCount * 6)
    }

    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    ) {
        self.draw(
            encoder: encoder,
            features: features,
            peaks: Array(repeating: 0, count: AudioFeatures.spectrumBandCount),
            time: time,
            drawableSize: drawableSize,
            pipelines: pipelines
        )
    }
}

enum OscilloscopeColumnSampler {
    /// Downsamples a mono waveform to display columns using Webamp's slice-first bucketing.
    static func columns(from waveform: [Float], count: Int) -> [Float] {
        guard count > 1, !waveform.isEmpty else {
            return Array(repeating: 0, count: max(count, 0))
        }

        var columns = Array(repeating: Float(0), count: count)
        let sourceCount = waveform.count
        let sliceWidth = max(1, sourceCount / count)

        for column in 0 ..< count {
            let index = min(column * sliceWidth, sourceCount - 1)
            columns[column] = Self.mapSampleToLineLevel(waveform[index])
        }

        return columns
    }

    /// Maps a float PCM sample to NDC using Winamp's byte-grid quantization for crisp scope pixels.
    private static func mapSampleToLineLevel(_ sample: Float) -> Float {
        let clamped = min(max(sample, -1), 1)
        let byte = (clamped * 0.5 + 0.5) * 255
        let row = round((byte / 16) * 2) - 9
        let clampedRow = min(max(row, 0), 14)
        return 1 - (clampedRow / 14) * 2
    }
}

final class MiniOscilloscopeMetalPlugin: MetalVisualizationPlugin {
    let kind: MetalVisualizationKind = .miniOscilloscope
    private var frozenColumns: [Float]?

    func reset() {
        self.frozenColumns = nil
    }

    func draw(
        encoder: MTLRenderCommandEncoder,
        features: AudioFeatures,
        time: CFTimeInterval,
        drawableSize: CGSize,
        pipelines: MetalPipelineProvider
    ) {
        let columnCount = AudioFeatures.scopeColumnCount(forWidth: drawableSize.width)
        let columns = self.resolvedColumns(
            features: features,
            columnCount: columnCount
        )

        guard let pipeline = pipelines.oscilloscopePipeline,
              let columnBuffer = pipelines.updateScopeColumnBuffer(columns),
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
                      scopeSampleCount: UInt32(columnCount)
                  )
              )
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(columnBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: columnCount)
    }

    private func resolvedColumns(features: AudioFeatures, columnCount: Int) -> [Float] {
        let mono = zip(features.waveformLeft, features.waveformRight).map { ($0 + $1) * 0.5 }

        if features.isPlaying {
            let columns = OscilloscopeColumnSampler.columns(from: mono, count: columnCount)
            self.frozenColumns = columns
            return columns
        }

        if let frozenColumns = self.frozenColumns, frozenColumns.count == columnCount {
            return frozenColumns
        }

        if let frozenColumns = self.frozenColumns, !frozenColumns.isEmpty {
            return Self.resample(frozenColumns, to: columnCount)
        }

        return OscilloscopeColumnSampler.columns(from: mono, count: columnCount)
    }

    private static func resample(_ values: [Float], to count: Int) -> [Float] {
        guard count > 0, !values.isEmpty else { return Array(repeating: 0, count: max(count, 0)) }
        if values.count == count { return values }

        return (0 ..< count).map { index in
            let source = Float(index) / Float(max(count - 1, 1)) * Float(values.count - 1)
            let lower = Int(floor(source))
            let upper = min(lower + 1, values.count - 1)
            let fraction = source - Float(lower)
            return values[lower] + (values[upper] - values[lower]) * fraction
        }
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

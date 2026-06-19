import Metal
@testable import Winamp
import XCTest

/// Headless GPU smoke tests for the Metal visualization path: every pipeline must compile, and
/// every plugin / fullscreen preset must encode commands that render to an offscreen target
/// without a GPU error. This turns a broken shader (e.g. a malformed fullscreen preset) from a
/// silent black panel + runtime log into a test failure.
///
/// Skips cleanly when no Metal device is available (e.g. a headless CI runner without a GPU), so
/// it never produces false failures — it adds coverage where a GPU exists (local + the
/// Apple-Silicon CI runner) and is a no-op elsewhere.
final class MetalVisualizationSmokeTests: XCTestCase {
    private var engine: MetalVisualizationEngine!

    /// Synthetic features with non-zero spectrum + waveform so the vertex shaders emit geometry.
    private static let features: AudioFeatures = {
        let spectrum = (0 ..< AudioFeatures.spectrumBandCount).map {
            Float($0) / Float(AudioFeatures.spectrumBandCount)
        }
        let wave = (0 ..< AudioFeatures.scopeWaveformSampleCount).map { sin(Float($0) * 0.05) }
        return AudioFeatures(spectrum: spectrum, waveformLeft: wave, waveformRight: wave, isPlaying: true)
    }()

    private static let drawableSize = CGSize(width: 64, height: 64)

    override func setUpWithError() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device available for GPU smoke tests")
        self.engine = MetalVisualizationEngine.shared
    }

    // MARK: - Pipeline compilation

    func testAllPipelinesCompile() {
        XCTAssertNotNil(self.engine.spectrumPipeline, "spectrum pipeline failed to compile")
        XCTAssertNotNil(self.engine.spectrumPeakPipeline, "spectrum peak pipeline failed to compile")
        XCTAssertNotNil(self.engine.spectrumCompositePipeline, "spectrum composite pipeline failed to compile")
        XCTAssertNotNil(self.engine.oscilloscopePipeline, "oscilloscope pipeline failed to compile")
        XCTAssertNotNil(self.engine.fullscreenPipeline, "fullscreen pipeline failed to compile")
        XCTAssertNotNil(self.engine.copyPipeline, "copy pipeline failed to compile")
    }

    // MARK: - Render smoke

    func testMiniSpectrumPluginRenders() throws {
        try self.assertRenders(MiniSpectrumMetalPlugin())
    }

    func testMiniAnalyzerPluginRenders() throws {
        try self.assertRenders(MiniAnalyzerMetalPlugin())
    }

    func testMiniOscilloscopePluginRenders() throws {
        try self.assertRenders(MiniOscilloscopeMetalPlugin())
    }

    func testAllFullscreenPresetsRender() throws {
        for preset in VisualizationPreset.allCases {
            try self.assertRenders(FullscreenMetalPlugin(preset: preset), label: preset.name)
        }
    }

    // MARK: - Helpers

    /// Encodes one plugin draw into a fresh offscreen target and asserts the GPU completes it
    /// without error.
    private func assertRenders(
        _ plugin: MetalVisualizationPlugin,
        label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let provider = MetalPipelineProvider()
        provider.advanceFrame()

        let texture = try XCTUnwrap(
            self.engine.makeOffscreenTexture(width: 64, height: 64), "offscreen texture", file: file, line: line
        )
        let commandBuffer = try XCTUnwrap(self.engine.commandQueue.makeCommandBuffer(), file: file, line: line)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: pass), file: file, line: line)
        plugin.draw(
            encoder: encoder,
            features: Self.features,
            time: 0.5,
            drawableSize: Self.drawableSize,
            pipelines: provider
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let context = label.isEmpty ? "" : " (\(label))"
        XCTAssertEqual(commandBuffer.status, .completed, "render did not complete\(context)", file: file, line: line)
        XCTAssertNil(commandBuffer.error, "GPU error\(context): \(String(describing: commandBuffer.error))", file: file, line: line)
    }
}

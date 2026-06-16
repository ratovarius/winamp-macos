import simd
@testable import Winamp
import XCTest

/// Asserts the Swift `VizUniforms` memory layout matches the byte offsets the Metal shader
/// reads (VisualizerShaders.metal), which also carries a `static_assert` on size/alignment.
/// Together they catch a field reorder/insert on either side before it silently corrupts every
/// visualization (the uniforms are `memcpy`'d straight into the GPU buffer).
final class VizUniformsLayoutTests: XCTestCase {
    func testStrideAndAlignmentMatchShader() {
        XCTAssertEqual(MemoryLayout<VizUniforms>.stride, 48)
        XCTAssertEqual(MemoryLayout<VizUniforms>.alignment, 8)
    }

    func testFieldOffsetsMatchShader() {
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.time), 0)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.bass), 4)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.mid), 8)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.treble), 12)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.resolution), 16)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.mode), 24)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.preset), 28)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.energy), 32)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.spectrumBandCount), 36)
        XCTAssertEqual(MemoryLayout<VizUniforms>.offset(of: \.scopeSampleCount), 40)
    }
}

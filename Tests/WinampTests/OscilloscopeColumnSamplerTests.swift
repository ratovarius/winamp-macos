@testable import Winamp
import XCTest

final class OscilloscopeColumnSamplerTests: XCTestCase {
    func testColumnCountMatchesRequest() {
        let waveform = (0 ..< 512).map { index in
            sin(Float(index) / 20)
        }
        let columns = OscilloscopeColumnSampler.columns(from: waveform, count: 300)
        XCTAssertEqual(columns.count, 300)
    }

    func testScopeColumnCountScalesWithDrawableWidth() {
        XCTAssertEqual(AudioFeatures.scopeColumnCount(forWidth: 80), 120)
        XCTAssertEqual(AudioFeatures.scopeColumnCount(forWidth: 185), 185)
        XCTAssertEqual(AudioFeatures.scopeColumnCount(forWidth: 900), 512)
    }

    func testFrozenColumnsPreserveWaveformShape() {
        let waveform = (0 ..< 256).map { index in
            sin(Float(index) / 8)
        }
        let wide = OscilloscopeColumnSampler.columns(from: waveform, count: 200)
        let narrow = OscilloscopeColumnSampler.columns(from: waveform, count: 120)
        XCTAssertNotEqual(wide, Array(repeating: 0, count: 200))
        XCTAssertNotEqual(narrow, Array(repeating: 0, count: 120))
    }
}

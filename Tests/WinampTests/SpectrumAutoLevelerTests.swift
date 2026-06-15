import XCTest

@testable import Winamp

final class SpectrumAutoLevelerTests: XCTestCase {
    func testQuietSignalIsExpandedAfterNormalization() {
        var leveler = SpectrumAutoLeveler()
        let quiet = Array(repeating: Float(0.05), count: AudioFeatures.spectrumBandCount)
        var normalized = quiet
        for _ in 0 ..< 30 {
            normalized = leveler.normalize(quiet)
        }
        XCTAssertGreaterThan(normalized.max() ?? 0, 0.2)
    }

    func testLoudSignalStaysNearOne() {
        var leveler = SpectrumAutoLeveler()
        let loud = Array(repeating: Float(0.9), count: AudioFeatures.spectrumBandCount)
        let normalized = leveler.normalize(loud)
        XCTAssertGreaterThan(normalized.min() ?? 0, 0.5)
    }

    func testResetRestoresBaseline() {
        var leveler = SpectrumAutoLeveler()
        _ = leveler.normalize(Array(repeating: 0.95, count: AudioFeatures.spectrumBandCount))
        leveler.reset()
        let afterReset = leveler.normalize(Array(repeating: 0.12, count: AudioFeatures.spectrumBandCount))
        XCTAssertGreaterThan(afterReset.max() ?? 0, 0.1)
    }
}

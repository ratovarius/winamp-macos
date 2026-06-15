@testable import Winamp
import XCTest

final class SpectrumPeakTrackerTests: XCTestCase {
    func testPeakTrackerHoldsThenFalls() {
        var tracker = SpectrumPeakTracker()
        let impulse = Array(repeating: Float(1), count: AudioFeatures.spectrumBandCount)

        let first = tracker.update(targets: impulse, isPlaying: true, deltaTime: 1.0 / 60.0)
        XCTAssertEqual(first.bars[0], 1, accuracy: 0.001)
        XCTAssertEqual(first.peaks[0], 1, accuracy: 0.001)

        let silence = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)
        var lastPeaks = first.peaks
        for _ in 0 ..< 30 {
            lastPeaks = tracker.update(targets: silence, isPlaying: true, deltaTime: 1.0 / 60.0).peaks
        }

        XCTAssertLessThan(lastPeaks[0], first.peaks[0])
        XCTAssertGreaterThan(lastPeaks[0], 0)
    }

    func testPeakTrackerResets() {
        var tracker = SpectrumPeakTracker()
        let impulse = Array(repeating: Float(1), count: AudioFeatures.spectrumBandCount)
        _ = tracker.update(targets: impulse, isPlaying: true, deltaTime: 1.0 / 60.0)
        tracker.reset()
        let cleared = tracker.update(
            targets: Array(repeating: 0, count: AudioFeatures.spectrumBandCount),
            isPlaying: false,
            deltaTime: 1.0 / 60.0
        )
        XCTAssertEqual(cleared.bars[0], 0)
        XCTAssertEqual(cleared.peaks[0], 0)
    }
}

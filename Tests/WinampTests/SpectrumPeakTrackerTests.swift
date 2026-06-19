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

    /// The tracker returns reused internal storage for both bars and peaks; previously returned
    /// arrays must stay stable across later `update` calls (copy-on-write value semantics), and the
    /// two returned arrays must be independent. Guards the per-frame allocation optimization.
    func testPreviouslyReturnedArraysAreStableAndIndependent() {
        var tracker = SpectrumPeakTracker()
        let impulse = Array(repeating: Float(1), count: AudioFeatures.spectrumBandCount)

        let first = tracker.update(targets: impulse, isPlaying: true, deltaTime: 1.0 / 60.0)
        let firstBar = first.bars[0]
        let firstPeak = first.peaks[0]
        XCTAssertNotEqual(first.bars, first.peaks, "bars and peaks must be independent arrays")

        let silence = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)
        for _ in 0 ..< 10 {
            _ = tracker.update(targets: silence, isPlaying: true, deltaTime: 1.0 / 60.0)
        }

        XCTAssertEqual(first.bars[0], firstBar, accuracy: 0, "previously returned bars mutated")
        XCTAssertEqual(first.peaks[0], firstPeak, accuracy: 0, "previously returned peaks mutated")
    }
}

@testable import Winamp
import XCTest

final class VisualizationFeatureSmootherTests: XCTestCase {
    func testAttackReachesTargetFasterThanRelease() {
        var smoother = VisualizationFeatureSmoother()
        let targets = Array(repeating: Float(1), count: AudioFeatures.spectrumBandCount)

        let afterAttack = smoother.update(targets: targets, isPlaying: true, deltaTime: 0.016)
        XCTAssertGreaterThan(afterAttack[0], 0.5)

        let held = smoother.update(targets: Array(repeating: 0, count: AudioFeatures.spectrumBandCount), isPlaying: false, deltaTime: 0.016)
        XCTAssertLessThan(held[0], afterAttack[0])
    }

    func testQuietTargetsAreNotInflatedByPriorPeaks() {
        var smoother = VisualizationFeatureSmoother()
        _ = smoother.update(
            targets: Array(repeating: Float(1), count: AudioFeatures.spectrumBandCount),
            isPlaying: true,
            deltaTime: 0.05
        )
        let quiet = smoother.update(
            targets: Array(repeating: Float(0.1), count: AudioFeatures.spectrumBandCount),
            isPlaying: true,
            deltaTime: 0.05
        )
        XCTAssertLessThan(quiet[0], 0.55)
    }

    /// The smoother returns its own reused state storage; a previously returned array must remain a
    /// stable value snapshot after later `update` calls (copy-on-write value semantics). Guards the
    /// per-frame allocation optimization against a future change that returns aliased mutable state.
    func testPreviouslyReturnedArrayIsStableAfterLaterUpdates() {
        var smoother = VisualizationFeatureSmoother()
        let loud = Array(repeating: Float(1), count: AudioFeatures.spectrumBandCount)

        let first = smoother.update(targets: loud, isPlaying: true, deltaTime: 0.016)
        let firstValue = first[0]
        XCTAssertGreaterThan(firstValue, 0)

        // Drive several more frames; `first` must not change retroactively.
        for _ in 0 ..< 5 {
            _ = smoother.update(targets: loud, isPlaying: true, deltaTime: 0.016)
        }

        XCTAssertEqual(first[0], firstValue, accuracy: 0, "previously returned spectrum mutated")
    }
}

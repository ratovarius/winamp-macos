import XCTest

@testable import Winamp

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
}

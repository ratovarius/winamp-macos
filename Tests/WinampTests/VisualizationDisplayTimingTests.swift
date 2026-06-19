import XCTest

@testable import Winamp

final class VisualizationDisplayTimingTests: XCTestCase {
    func testReturns60ForStandardDisplays() {
        XCTAssertEqual(VisualizationDisplayTiming.preferredFramesPerSecond(maximumFramesPerSecond: nil), 60)
        XCTAssertEqual(VisualizationDisplayTiming.preferredFramesPerSecond(maximumFramesPerSecond: 60), 60)
    }

    func testCapsProMotionAt120() {
        XCTAssertEqual(VisualizationDisplayTiming.preferredFramesPerSecond(maximumFramesPerSecond: 240), 120)
    }

    func testUsesProMotionWhenAbove60() {
        XCTAssertEqual(VisualizationDisplayTiming.preferredFramesPerSecond(maximumFramesPerSecond: 120), 120)
    }
}

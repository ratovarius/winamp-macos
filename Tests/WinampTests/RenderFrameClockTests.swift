import QuartzCore
import XCTest

@testable import Winamp

final class RenderFrameClockTests: XCTestCase {
    /// Deterministic clock whose time the test advances by hand.
    private final class FakeClock: VisualizationClock, @unchecked Sendable {
        var time: CFTimeInterval
        init(start: CFTimeInterval) { self.time = start }
        func now() -> CFTimeInterval { self.time }
    }

    func testFirstTickReportsZeroElapsedAndDelta() {
        let clock = FakeClock(start: 100)
        var frameClock = RenderFrameClock(clock: clock)

        let tick = frameClock.tick()
        XCTAssertEqual(tick.now, 100, accuracy: 0.0001)
        XCTAssertEqual(tick.elapsed, 0, accuracy: 0.0001)
        XCTAssertEqual(tick.delta, 0, accuracy: 0.0001)
    }

    func testElapsedAccumulatesWhileDeltaIsPerFrame() {
        let clock = FakeClock(start: 10)
        var frameClock = RenderFrameClock(clock: clock)

        clock.time = 10.5
        var tick = frameClock.tick()
        XCTAssertEqual(tick.elapsed, 0.5, accuracy: 0.0001)
        XCTAssertEqual(tick.delta, 0.5, accuracy: 0.0001)

        clock.time = 10.75
        tick = frameClock.tick()
        XCTAssertEqual(tick.elapsed, 0.75, accuracy: 0.0001)
        XCTAssertEqual(tick.delta, 0.25, accuracy: 0.0001)
    }

    func testResetDeltaShrinksNextDeltaButKeepsElapsedEpoch() {
        let clock = FakeClock(start: 0)
        var frameClock = RenderFrameClock(clock: clock)

        // Simulate a long pause.
        clock.time = 5
        frameClock.resetDelta()

        clock.time = 5.016
        let tick = frameClock.tick()
        // Delta is measured from the reset, not from the start of the pause.
        XCTAssertEqual(tick.delta, 0.016, accuracy: 0.0001)
        // Elapsed is still measured from the clock's creation epoch.
        XCTAssertEqual(tick.elapsed, 5.016, accuracy: 0.0001)
    }
}

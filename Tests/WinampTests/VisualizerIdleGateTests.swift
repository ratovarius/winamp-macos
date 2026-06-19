import XCTest

@testable import Winamp

final class VisualizerIdleGateTests: XCTestCase {
    func testStaysAwakeWhileActive() {
        var gate = VisualizerIdleGate(holdDuration: 1.0)
        for _ in 0 ..< 200 {
            XCTAssertFalse(gate.update(isActive: true, deltaTime: 1.0 / 60))
        }
        XCTAssertFalse(gate.isPaused)
    }

    func testPausesAfterHoldDurationOfInactivity() {
        var gate = VisualizerIdleGate(holdDuration: 1.0)

        // Just under the hold window: still awake.
        XCTAssertFalse(gate.update(isActive: false, deltaTime: 0.9))
        XCTAssertFalse(gate.isPaused)

        // Crossing the hold window: pauses.
        XCTAssertTrue(gate.update(isActive: false, deltaTime: 0.2))
        XCTAssertTrue(gate.isPaused)
    }

    func testActivityResetsIdleProgress() {
        var gate = VisualizerIdleGate(holdDuration: 1.0)

        gate.update(isActive: false, deltaTime: 0.9)
        // A single active frame restarts the idle window.
        gate.update(isActive: true, deltaTime: 1.0 / 60)
        XCTAssertEqual(gate.idleElapsed, 0)

        XCTAssertFalse(gate.update(isActive: false, deltaTime: 0.9))
        XCTAssertTrue(gate.update(isActive: false, deltaTime: 0.2))
    }

    func testWakeClearsPausedState() {
        var gate = VisualizerIdleGate(holdDuration: 0.5)
        XCTAssertTrue(gate.update(isActive: false, deltaTime: 0.6))
        XCTAssertTrue(gate.isPaused)

        gate.wake()
        XCTAssertFalse(gate.isPaused)
        XCTAssertEqual(gate.idleElapsed, 0)
    }

    func testNegativeDeltaIsIgnored() {
        var gate = VisualizerIdleGate(holdDuration: 1.0)
        XCTAssertFalse(gate.update(isActive: false, deltaTime: -5.0))
        XCTAssertEqual(gate.idleElapsed, 0)
    }
}

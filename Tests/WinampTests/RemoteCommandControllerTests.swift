@testable import Winamp
import XCTest

@MainActor
final class RemoteCommandControllerTests: XCTestCase {
    func testEachCommandRoutesToItsHandler() {
        let controller = RemoteCommandController()
        var fired: [String] = []
        controller.setHandlers(RemoteCommandController.Handlers(
            play: { fired.append("play") },
            pause: { fired.append("pause") },
            toggle: { fired.append("toggle") },
            next: { fired.append("next") },
            previous: { fired.append("previous") }
        ))

        controller.performPlay()
        controller.performPause()
        controller.performToggle()
        controller.performNext()
        controller.performPrevious()

        // Order + identity catches copy-paste wiring bugs (e.g. next/previous swapped).
        XCTAssertEqual(fired, ["play", "pause", "toggle", "next", "previous"])
    }

    func testDefaultHandlersAreNoOps() {
        let controller = RemoteCommandController()
        // Invoking before handlers are wired must be safe (no crash).
        controller.performPlay()
        controller.performPause()
        controller.performToggle()
        controller.performNext()
        controller.performPrevious()
    }

    func testSetHandlersReplacesPreviousHandlers() {
        let controller = RemoteCommandController()
        var firstCount = 0
        controller.setHandlers(RemoteCommandController.Handlers(play: { firstCount += 1 }))
        controller.performPlay()

        var secondCount = 0
        controller.setHandlers(RemoteCommandController.Handlers(play: { secondCount += 1 }))
        controller.performPlay()

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
    }
}

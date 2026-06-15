@testable import Winamp
import XCTest

final class DisplayModeTests: XCTestCase {
    func testDisplayModeCyclesThroughAllModes() {
        XCTAssertEqual(DisplayMode.scrolling.cycled(), .vestaboard)
        XCTAssertEqual(DisplayMode.vestaboard.cycled(), .scrollingUp)
        XCTAssertEqual(DisplayMode.scrollingUp.cycled(), .pixelated)
        XCTAssertEqual(DisplayMode.pixelated.cycled(), .scrolling)
    }

    func testDisplayModeCycleCompletesFullLoop() {
        let backToStart = DisplayMode.scrolling
            .cycled()
            .cycled()
            .cycled()
            .cycled()
        XCTAssertEqual(backToStart, .scrolling)
    }
}

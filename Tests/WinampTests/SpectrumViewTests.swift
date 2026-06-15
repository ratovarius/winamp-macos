@testable import Winamp
import XCTest

final class SpectrumViewTests: XCTestCase {
    func testVisualizationModeFromStorageValue() {
        XCTAssertEqual(VisualizationMode.from(storageValue: 0), .bars)
        XCTAssertEqual(VisualizationMode.from(storageValue: 1), .oscilloscope)
        XCTAssertEqual(VisualizationMode.from(storageValue: 99), .oscilloscope)
    }

    func testVisualizationModeStorageRoundTrip() {
        XCTAssertEqual(VisualizationMode.bars.storageValue, 0)
        XCTAssertEqual(VisualizationMode.oscilloscope.storageValue, 1)
    }

    func testVisualizationModeToggle() {
        XCTAssertEqual(VisualizationMode.bars.toggled(), .oscilloscope)
        XCTAssertEqual(VisualizationMode.oscilloscope.toggled(), .bars)
        XCTAssertEqual(VisualizationMode.bars.toggled().toggled(), .bars)
    }
}

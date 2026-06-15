@testable import Winamp
import XCTest

final class SpectrumViewTests: XCTestCase {
    func testVisualizationModeFromStorageValue() {
        XCTAssertEqual(VisualizationMode.from(storageValue: 0), .bars)
        XCTAssertEqual(VisualizationMode.from(storageValue: 1), .oscilloscope)
        XCTAssertEqual(VisualizationMode.from(storageValue: 2), .analyzer)
        XCTAssertEqual(VisualizationMode.from(storageValue: 99), .bars)
    }

    func testVisualizationModeStorageRoundTrip() {
        XCTAssertEqual(VisualizationMode.bars.storageValue, 0)
        XCTAssertEqual(VisualizationMode.oscilloscope.storageValue, 1)
        XCTAssertEqual(VisualizationMode.analyzer.storageValue, 2)
    }

    func testVisualizationModeCyclesThroughAllModes() {
        XCTAssertEqual(VisualizationMode.bars.advanced(), .oscilloscope)
        XCTAssertEqual(VisualizationMode.oscilloscope.advanced(), .analyzer)
        XCTAssertEqual(VisualizationMode.analyzer.advanced(), .bars)
        XCTAssertEqual(VisualizationMode.bars.advanced().advanced().advanced(), .bars)
    }
}

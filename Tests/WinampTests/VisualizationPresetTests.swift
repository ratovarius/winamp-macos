@testable import Winamp
import XCTest

final class VisualizationPresetTests: XCTestCase {
    func testAllPresetsHaveUniqueRawValues() {
        let rawValues = VisualizationPreset.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
    }

    func testAllPresetsHaveNonEmptyNames() {
        for preset in VisualizationPreset.allCases {
            XCTAssertFalse(preset.name.isEmpty, "Missing name for preset \(preset.rawValue)")
        }
    }

    func testPresetNamesAreStable() {
        XCTAssertEqual(VisualizationPreset.spiralGalaxy.name, "Spiral Galaxy")
        XCTAssertEqual(VisualizationPreset.starWarsCrawl.name, "Star Wars Crawl")
    }

    func testPresetAdvancedByStepWrapsAround() {
        XCTAssertEqual(VisualizationPreset.starWarsCrawl.advanced(by: 1), .spiralGalaxy)
        XCTAssertEqual(VisualizationPreset.spiralGalaxy.advanced(by: -1), .starWarsCrawl)
        XCTAssertEqual(VisualizationPreset.spiralGalaxy.advanced(by: 2), .plasmaField)
    }
}

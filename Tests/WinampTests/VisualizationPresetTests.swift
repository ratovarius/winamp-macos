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

    /// Guards the Swift↔shader contract: every preset must have its own branch in
    /// `fullscreenFragment`. If this count changes, add/remove the matching shader branch
    /// (and bump the literal here) so presets never silently alias via wraparound.
    func testPresetCountMatchesShaderBranchCount() {
        XCTAssertEqual(VisualizationPreset.shaderBranchCount, 11)
        XCTAssertEqual(VisualizationPreset.allCases.count, VisualizationPreset.shaderBranchCount)
    }

    func testPresetRawValuesAreContiguousFromZero() {
        // The shader dispatches on rawValue with no gaps; a hole would render the final `else`.
        let sortedRawValues = VisualizationPreset.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(sortedRawValues, Array(0 ..< VisualizationPreset.allCases.count))
    }
}

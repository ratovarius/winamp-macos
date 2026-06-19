import XCTest
@testable import Winamp

final class EQFParserTests: XCTestCase {
    /// Build a minimal valid .eqf with a single preset for testing.
    private func makeEQF(name: String, bandBytes: [UInt8], preampByte: UInt8) -> Data {
        var bytes = [UInt8](EQFParser.header.utf8)
        bytes.append(contentsOf: [0x1A, 0x21, 0x2D, 0x2D])
        var nameField = [UInt8](name.utf8)
        nameField.append(contentsOf: Array(repeating: 0, count: 257 - nameField.count))
        bytes.append(contentsOf: nameField)
        bytes.append(contentsOf: bandBytes) // 10 bands (stored = 64 - value)
        bytes.append(preampByte)
        return Data(bytes)
    }

    func testRejectsInvalidHeader() {
        let bogus = Data("not a winamp file".utf8)
        XCTAssertThrowsError(try EQFParser.parse(bogus))
    }

    func testParsesSinglePresetNameAndCount() throws {
        // Stored byte 64 - value: value 32 -> stored 32 (~0 dB midpoint).
        let data = makeEQF(name: "MyPreset", bandBytes: Array(repeating: 32, count: 10), preampByte: 32)
        let presets = try EQFParser.parse(data)
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets[0].name, "MyPreset")
        XCTAssertEqual(presets[0].bandGainsDB.count, 10)
    }

    func testValueExtremesMapToFullRange() throws {
        // value 64 (max boost) -> stored 0; value 1 (min) -> stored 63.
        let maxData = makeEQF(name: "Max", bandBytes: Array(repeating: 0, count: 10), preampByte: 0)
        let maxPreset = try EQFParser.parse(maxData)[0]
        XCTAssertEqual(maxPreset.bandGainsDB[0], 12, accuracy: 0.01)

        let minData = makeEQF(name: "Min", bandBytes: Array(repeating: 63, count: 10), preampByte: 63)
        let minPreset = try EQFParser.parse(minData)[0]
        XCTAssertEqual(minPreset.bandGainsDB[0], -12, accuracy: 0.01)
    }

    func testRoundTripPreservesGainsWithinQuantization() throws {
        let original = EQPreset(
            id: "rt",
            name: "RoundTrip",
            bandGainsDB: [6, -6, 0, 12, -12, 3, -3, 9, -9, 1.5],
            preampGainDB: 4
        )
        let encoded = EQFParser.write([original])
        let decoded = try EQFParser.parse(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "RoundTrip")
        // ±12 dB across 64 steps => ~0.38 dB/step; allow one step of error.
        for (a, b) in zip(decoded[0].bandGainsDB, original.bandGainsDB) {
            XCTAssertEqual(a, b, accuracy: 0.5)
        }
        XCTAssertEqual(decoded[0].preampGainDB, original.preampGainDB, accuracy: 0.5)
    }
}

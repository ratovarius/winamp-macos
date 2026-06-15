import Foundation

/// Parses and writes Winamp equalizer preset files (`.eqf` / `.q1`).
///
/// Format (Winamp EQ library v1.1):
///   - 27-byte ASCII header: "Winamp EQ library file v1.1"
///   - 4 bytes: "\u{1A}!--" separator
///   - per preset:
///       - 257-byte null-terminated name
///       - 11 bytes: 10 band levels (60…16k Hz) then preamp, each stored as
///         `64 - value` (inverted, 1…64 where higher = louder)
///
/// Band/preamp byte values (1…64) map to ±12 dB: value 1 = −12 dB, ~33 = 0 dB,
/// 64 = +12 dB. Mirrors Webamp's `winamp-eqf` and `normalizeEqBand`.
enum EQFParser {
    static let header = "Winamp EQ library file v1.1"
    private static let nameLength = 257
    private static let bandCount = 10

    enum EQFError: Error, LocalizedError {
        case invalidHeader
        case truncated

        var errorDescription: String? {
            switch self {
            case .invalidHeader: "Not a valid Winamp .eqf file."
            case .truncated: "The .eqf file is incomplete or corrupted."
            }
        }
    }

    /// Decode every preset in an `.eqf`/`.q1` file.
    static func parse(_ data: Data) throws -> [EQPreset] {
        let bytes = [UInt8](data)
        guard bytes.count >= header.count + 4 else { throw EQFError.truncated }

        let headerBytes = bytes.prefix(header.count)
        guard String(decoding: headerBytes, as: UTF8.self) == header else {
            throw EQFError.invalidHeader
        }

        var i = header.count + 4 // skip header + "\u{1A}!--" separator
        var presets: [EQPreset] = []

        while i + nameLength + bandCount + 1 <= bytes.count {
            let nameField = bytes[i ..< (i + nameLength)]
            let nameBytes = Array(nameField.prefix { $0 != 0 })
            let name = String(decoding: nameBytes, as: UTF8.self)
            i += nameLength

            var gains: [Float] = []
            for _ in 0 ..< bandCount {
                gains.append(eqfValueToDB(Int(bytes[i])))
                i += 1
            }
            let preamp = eqfValueToDB(Int(bytes[i]))
            i += 1

            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            presets.append(EQPreset(
                id: "eqf-\(presets.count)-\(trimmed.lowercased())",
                name: trimmed.isEmpty ? "Preset \(presets.count + 1)" : trimmed,
                bandGainsDB: gains,
                preampGainDB: preamp
            ))
        }

        guard !presets.isEmpty else { throw EQFError.truncated }
        return presets
    }

    /// Encode presets back into `.eqf` bytes.
    static func write(_ presets: [EQPreset]) -> Data {
        var bytes = [UInt8](header.utf8)
        bytes.append(contentsOf: [0x1A, 0x21, 0x2D, 0x2D]) // "\u{1A}!--"

        for preset in presets {
            var nameField = [UInt8](preset.name.utf8).prefix(nameLength - 1).map { $0 }
            nameField.append(contentsOf: Array(repeating: 0, count: nameLength - nameField.count))
            bytes.append(contentsOf: nameField)

            let gains = normalizedBands(preset.bandGainsDB)
            for gain in gains {
                bytes.append(dbToEQFValue(gain))
            }
            bytes.append(dbToEQFValue(preset.preampGainDB))
        }
        return Data(bytes)
    }

    // MARK: - Value conversion

    /// EQF byte (1…64) → dB (−12…+12). The byte is already de-inverted by callers
    /// reading `bytes[i]`; Winamp stores `64 - value`, so undo that here.
    private static func eqfValueToDB(_ stored: Int) -> Float {
        let value = 64 - stored // de-invert
        let normalized = Float(value - 1) / 63 // 0…1
        return (normalized * 2 - 1) * 12
    }

    private static func dbToEQFValue(_ db: Float) -> UInt8 {
        let normalized = (max(-12, min(12, db)) / 12 + 1) / 2 // 0…1
        let value = Int((normalized * 63).rounded()) + 1 // 1…64
        return UInt8(64 - max(1, min(64, value))) // re-invert
    }

    private static func normalizedBands(_ gains: [Float]) -> [Float] {
        if gains.count == bandCount { return gains }
        var padded = gains
        padded += Array(repeating: 0, count: max(0, bandCount - padded.count))
        return Array(padded.prefix(bandCount))
    }
}

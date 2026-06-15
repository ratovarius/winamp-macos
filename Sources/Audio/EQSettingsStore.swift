import Foundation

struct EQSettings: Codable, Equatable {
    var bandGainsDB: [Float]
    var preampGainDB: Float
    var eqEnabled: Bool
    var autoEnabled: Bool

    static let bandCount = 10
    static let defaultBandGainsDB = Array(repeating: Float(0), count: bandCount)

    static let `default` = EQSettings(
        bandGainsDB: defaultBandGainsDB,
        preampGainDB: 0,
        eqEnabled: true,
        autoEnabled: false
    )
}

struct EQPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var bandGainsDB: [Float]
    var preampGainDB: Float

    static let builtIn: [EQPreset] = [
        EQPreset(id: "flat", name: "Flat", bandGainsDB: Array(repeating: 0, count: 10), preampGainDB: 0),
        EQPreset(id: "rock", name: "Rock", bandGainsDB: [5, 4, 3, 1, -1, -1, 0, 2, 3, 4], preampGainDB: 0),
        EQPreset(id: "pop", name: "Pop", bandGainsDB: [-1, 2, 4, 5, 3, 0, -1, -1, -1, -1], preampGainDB: 0),
        EQPreset(id: "jazz", name: "Jazz", bandGainsDB: [3, 2, 1, 2, -2, -2, 0, 1, 2, 3], preampGainDB: 0),
        EQPreset(id: "classical", name: "Classical", bandGainsDB: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4], preampGainDB: 0),
        EQPreset(id: "bass", name: "Bass Boost", bandGainsDB: [8, 6, 4, 2, 0, 0, 0, 0, 0, 0], preampGainDB: 0),
        EQPreset(id: "treble", name: "Treble Boost", bandGainsDB: [0, 0, 0, 0, 0, 2, 4, 6, 7, 8], preampGainDB: 0),
    ]
}

final class EQSettingsStore {
    private let settingsKey: String
    private let presetsKey: String
    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        settingsKey: String = "WinampEQSettings",
        presetsKey: String = "WinampEQPresets"
    ) {
        self.userDefaults = userDefaults
        self.settingsKey = settingsKey
        self.presetsKey = presetsKey
    }

    func loadSettings() -> EQSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(EQSettings.self, from: data),
              settings.bandGainsDB.count == EQSettings.bandCount
        else {
            return .default
        }
        return settings
    }

    func saveSettings(_ settings: EQSettings) {
        guard settings.bandGainsDB.count == EQSettings.bandCount,
              let data = try? JSONEncoder().encode(settings)
        else {
            return
        }
        self.userDefaults.set(data, forKey: self.settingsKey)
    }

    func loadPresets() -> [EQPreset] {
        guard let data = userDefaults.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([EQPreset].self, from: data),
              !presets.isEmpty
        else {
            return EQPreset.builtIn
        }
        return presets
    }

    func savePresets(_ presets: [EQPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        self.userDefaults.set(data, forKey: self.presetsKey)
    }

    func applyPreset(_ preset: EQPreset, to settings: inout EQSettings) {
        settings.bandGainsDB = preset.bandGainsDB
        settings.preampGainDB = preset.preampGainDB
    }
}

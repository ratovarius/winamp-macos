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

    /// "Flat" plus the 17 canonical Winamp presets, derived from the Winamp EQ
    /// library (`winamp.q1`, via Webamp's `builtin.json`). EQF values (1–64) were
    /// mapped to ±12 dB and snapped to flat near the midpoint, matching Winamp.
    static let builtIn: [EQPreset] = [
        EQPreset(id: "flat", name: "Flat", bandGainsDB: Array(repeating: 0, count: 10), preampGainDB: 0),
        EQPreset(id: "classical", name: "Classical", bandGainsDB: [0, 0, 0, 0, 0, 0, -4.8, -4.8, -4.8, -6.3], preampGainDB: 0),
        EQPreset(id: "club", name: "Club", bandGainsDB: [0, 0, 2.1, 3.6, 3.6, 3.6, 2.1, 0, 0, 0], preampGainDB: 0),
        EQPreset(id: "dance", name: "Dance", bandGainsDB: [5.9, 4.4, 1.3, 0, 0, -4, -4.8, -4.8, 0, 0], preampGainDB: 0),
        EQPreset(id: "laptop", name: "Laptop speakers/headphones", bandGainsDB: [2.9, 6.7, 3.2, -2.5, -1.7, 0, 2.9, 5.9, 7.8, 9], preampGainDB: 0),
        EQPreset(id: "large-hall", name: "Large hall", bandGainsDB: [6.3, 6.3, 3.6, 3.6, 0, -3.2, -3.2, -3.2, 0, 0], preampGainDB: 0),
        EQPreset(id: "party", name: "Party", bandGainsDB: [4.4, 4.4, 0, 0, 0, 0, 0, 0, 4.4, 4.4], preampGainDB: 0),
        EQPreset(id: "pop", name: "Pop", bandGainsDB: [-1.3, 2.9, 4.4, 4.8, 3.2, 0, -1.7, -1.7, -1.3, -1.3], preampGainDB: 0),
        EQPreset(id: "reggae", name: "Reggae", bandGainsDB: [0, 0, 0, -4, 0, 4, 4, 0, 0, 0], preampGainDB: 0),
        EQPreset(id: "rock", name: "Rock", bandGainsDB: [4.8, 2.9, -3.6, -5.1, -2.5, 2.5, 5.5, 6.7, 6.7, 6.7], preampGainDB: 0),
        EQPreset(id: "soft", name: "Soft", bandGainsDB: [2.9, 0, 0, -1.7, 0, 2.5, 5.1, 5.9, 6.7, 7.4], preampGainDB: 0),
        EQPreset(id: "ska", name: "Ska", bandGainsDB: [-1.7, -3.2, -2.9, 0, 2.5, 3.6, 5.5, 5.9, 6.7, 5.9], preampGainDB: 0),
        EQPreset(id: "full-bass", name: "Full Bass", bandGainsDB: [5.9, 5.9, 5.9, 3.6, 0, -2.9, -5.5, -6.7, -7, -7], preampGainDB: 0),
        EQPreset(id: "soft-rock", name: "Soft Rock", bandGainsDB: [2.5, 2.5, 1.3, 0, -2.9, -3.6, -2.5, 0, 1.7, 5.5], preampGainDB: 0),
        EQPreset(id: "full-treble", name: "Full Treble", bandGainsDB: [-6.3, -6.3, -6.3, -2.9, 1.7, 6.7, 9.7, 9.7, 9.7, 10.5], preampGainDB: 0),
        EQPreset(id: "full-bass-treble", name: "Full Bass & Treble", bandGainsDB: [4.4, 3.6, 0, -4.8, -3.2, 0, 5.1, 6.7, 7.4, 7.4], preampGainDB: 0),
        EQPreset(id: "live", name: "Live", bandGainsDB: [-3.2, 0, 2.5, 3.2, 3.6, 3.6, 2.5, 1.7, 1.7, 1.3], preampGainDB: 0),
        EQPreset(id: "techno", name: "Techno", bandGainsDB: [4.8, 3.6, 0, -3.6, -3.2, 0, 4.8, 5.9, 5.9, 5.5], preampGainDB: 0),
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

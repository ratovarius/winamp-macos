@testable import Winamp
import XCTest

final class EQSettingsStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        super.setUp()
        self.suiteName = "winamp-eq-\(UUID().uuidString)"
        self.userDefaults = try XCTUnwrap(UserDefaults(suiteName: self.suiteName))
    }

    override func tearDown() {
        self.userDefaults.removePersistentDomain(forName: self.suiteName)
        super.tearDown()
    }

    func testSaveAndLoadSettingsRoundTrip() {
        let store = EQSettingsStore(userDefaults: userDefaults)
        var settings = EQSettings.default
        settings.bandGainsDB = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        settings.preampGainDB = 3
        settings.eqEnabled = false
        settings.autoEnabled = true

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded, settings)
    }

    func testLoadSettingsReturnsDefaultWhenMissing() {
        let store = EQSettingsStore(userDefaults: userDefaults)
        XCTAssertEqual(store.loadSettings(), .default)
    }

    func testLoadPresetsFallsBackToBuiltIn() {
        let store = EQSettingsStore(userDefaults: userDefaults)
        XCTAssertEqual(store.loadPresets(), EQPreset.builtIn)
    }

    func testSaveAndLoadCustomPresets() {
        let store = EQSettingsStore(userDefaults: userDefaults)
        let custom = [EQPreset(id: "mine", name: "Mine", bandGainsDB: Array(repeating: 2, count: 10), preampGainDB: 1)]
        store.savePresets(custom)
        XCTAssertEqual(store.loadPresets(), custom)
    }

    func testApplyPresetUpdatesSettings() throws {
        let store = EQSettingsStore(userDefaults: userDefaults)
        var settings = EQSettings.default
        try store.applyPreset(XCTUnwrap(EQPreset.builtIn.first { $0.id == "rock" }), to: &settings)
        XCTAssertEqual(settings.bandGainsDB, EQPreset.builtIn.first { $0.id == "rock" }?.bandGainsDB)
    }
}

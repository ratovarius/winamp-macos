@testable import Winamp
import XCTest

final class PlaylistStateStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        super.setUp()
        self.suiteName = "winamp-playlist-state-\(UUID().uuidString)"
        self.userDefaults = try XCTUnwrap(UserDefaults(suiteName: self.suiteName))
    }

    override func tearDown() {
        self.userDefaults.removePersistentDomain(forName: self.suiteName)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let store = PlaylistStateStore(userDefaults: userDefaults)
        let state = PersistedPlaylistState(
            trackPaths: ["/music/a.mp3", "/music/b.flac"],
            currentIndex: 1,
            shuffleEnabled: true,
            repeatEnabled: true
        )

        store.saveState(state)
        XCTAssertEqual(store.loadState(), state)
    }

    func testClearStateRemovesSavedData() {
        let store = PlaylistStateStore(userDefaults: userDefaults)
        store.saveState(PersistedPlaylistState(
            trackPaths: ["/music/a.mp3"],
            currentIndex: 0,
            shuffleEnabled: false,
            repeatEnabled: false
        ))

        store.clearState()
        XCTAssertNil(store.loadState())
    }
}

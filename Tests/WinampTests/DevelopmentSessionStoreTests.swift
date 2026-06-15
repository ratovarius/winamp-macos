@testable import Winamp
import XCTest

final class DevelopmentSessionStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUp()
        self.fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-session-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: self.fileURL)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = DevelopmentSessionStore(fileURL: self.fileURL)
        let snapshot = DevelopmentSessionSnapshot(
            volume: 0.42,
            eq: EQSettings(
                bandGainsDB: [1, 2, 0, 0, 0, 0, 0, 0, 0, 3],
                preampGainDB: -6,
                eqEnabled: true,
                autoEnabled: false
            ),
            playlist: PersistedPlaylistState(
                trackPaths: ["/music/a.mp3", "/music/b.flac"],
                currentIndex: 1,
                shuffleEnabled: true,
                repeatEnabled: false
            ),
            playback: DevelopmentSessionPlayback(positionSeconds: 93.5, wasPlaying: true)
        )

        store.save(snapshot)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.volume, snapshot.volume)
        XCTAssertEqual(loaded.eq, snapshot.eq)
        XCTAssertEqual(loaded.playlist, snapshot.playlist)
        XCTAssertEqual(loaded.playback, snapshot.playback)
        XCTAssertEqual(loaded.schemaVersion, snapshot.schemaVersion)
    }

    func testLoadReturnsNilForMissingFile() {
        let store = DevelopmentSessionStore(fileURL: self.fileURL)
        XCTAssertNil(store.load())
    }

    func testSavedJSONIsHumanReadable() throws {
        let store = DevelopmentSessionStore(fileURL: self.fileURL)
        store.save(DevelopmentSessionSnapshot(
            volume: 0.75,
            eq: .default,
            playlist: PersistedPlaylistState(
                trackPaths: ["/music/track.mp3"],
                currentIndex: 0,
                shuffleEnabled: false,
                repeatEnabled: false
            ),
            playback: nil
        ))

        let text = try String(contentsOf: self.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"volume\""))
        XCTAssertTrue(text.contains("\"trackPaths\""))
        XCTAssertTrue(text.contains("\"preampGainDB\""))
    }
}

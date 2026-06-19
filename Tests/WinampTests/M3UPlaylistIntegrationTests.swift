@testable import Winamp
import XCTest

@MainActor
final class M3UPlaylistIntegrationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("winamp-m3u-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.tempDirectory)
    }

    func testLoadM3UPlaylistResolvesExistingRelativeTrack() async throws {
        let bundle = Bundle(for: M3UPlaylistIntegrationTests.self)
        let wavURL = try XCTUnwrap(bundle.url(forResource: "short", withExtension: "wav"))
        let destWav = self.tempDirectory.appendingPathComponent("relative-track.wav")
        try FileManager.default.copyItem(at: wavURL, to: destWav)

        let m3uContent = """
        #EXTM3U
        relative-track.wav
        missing.mp3
        """
        let m3uURL = self.tempDirectory.appendingPathComponent("playlist.m3u")
        try m3uContent.write(to: m3uURL, atomically: true, encoding: .utf8)

        let manager = PlaylistManager(restoreBookmarks: false, restorePlaylist: false)
        let tracks = await manager.loadM3UPlaylist(from: m3uURL)
        XCTAssertEqual(tracks?.count, 1)
        XCTAssertEqual(tracks?[0].url?.lastPathComponent, "relative-track.wav")
        XCTAssertEqual(manager.test_bookmarkStore.bookmarkCount, 2)
    }
}

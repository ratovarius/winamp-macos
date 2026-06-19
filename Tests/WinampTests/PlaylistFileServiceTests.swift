@testable import Winamp
import XCTest

final class PlaylistFileServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("winamp-file-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.tempDirectory)
    }

    func testCollectAudioFilesFindsSupportedExtensions() {
        let wavURL = self.tempDirectory.appendingPathComponent("one.wav")
        let txtURL = self.tempDirectory.appendingPathComponent("notes.txt")
        FileManager.default.createFile(atPath: wavURL.path, contents: Data())
        FileManager.default.createFile(atPath: txtURL.path, contents: Data())

        let store = SecurityScopedBookmarkStore()
        let service = PlaylistFileService(bookmarkStore: store)
        let files = service.collectAudioFiles(in: self.tempDirectory)

        XCTAssertEqual(files.map(\.lastPathComponent), ["one.wav"])
    }

    func testCollectAudioFilesIncludesSubfolders() throws {
        let nested = self.tempDirectory.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let rootTrack = self.tempDirectory.appendingPathComponent("root.mp3")
        let nestedTrack = nested.appendingPathComponent("deep.flac")
        FileManager.default.createFile(atPath: rootTrack.path, contents: Data())
        FileManager.default.createFile(atPath: nestedTrack.path, contents: Data())

        let store = SecurityScopedBookmarkStore()
        let service = PlaylistFileService(bookmarkStore: store)
        let files = service.collectAudioFiles(in: self.tempDirectory).map(\.lastPathComponent).sorted()

        XCTAssertEqual(files, ["deep.flac", "root.mp3"])
    }

    func testResolvedLocalURLResolvesSymlinks() throws {
        let target = self.tempDirectory.appendingPathComponent("real.wav")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        let link = self.tempDirectory.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let store = SecurityScopedBookmarkStore()
        let service = PlaylistFileService(bookmarkStore: store)
        let resolved = service.resolvedLocalURL(link)

        XCTAssertEqual(resolved.standardizedFileURL, target.standardizedFileURL)
    }

    func testLoadM3UPlaylistSkipsTraversalEntries() async throws {
        let playlistURL = self.tempDirectory.appendingPathComponent("list.m3u")
        let insideURL = self.tempDirectory.appendingPathComponent("inside.wav")
        FileManager.default.createFile(atPath: insideURL.path, contents: Data())

        let outsideDir = self.tempDirectory.deletingLastPathComponent()
        let outsideURL = outsideDir.appendingPathComponent("outside-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: outsideURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        let content = """
        #EXTM3U
        inside.wav
        ../\(outsideURL.lastPathComponent)
        """
        try content.write(to: playlistURL, atomically: true, encoding: .utf8)

        let store = SecurityScopedBookmarkStore()
        store.saveBookmark(for: self.tempDirectory)
        let service = PlaylistFileService(bookmarkStore: store)

        let tracks = await service.loadM3UPlaylist(from: playlistURL)
        XCTAssertEqual(tracks?.count, 1)
        XCTAssertEqual(tracks?.first?.url?.lastPathComponent, "inside.wav")
    }

    func testLoadM3UPlaylistSkipsAbsolutePathsWithoutAccess() async throws {
        let playlistURL = self.tempDirectory.appendingPathComponent("list.m3u")
        let content = """
        #EXTM3U
        \(tempDirectory.appendingPathComponent("local.wav").path)
        /tmp/no-bookmark-\(UUID().uuidString).mp3
        """
        try content.write(to: playlistURL, atomically: true, encoding: .utf8)

        let localURL = self.tempDirectory.appendingPathComponent("local.wav")
        FileManager.default.createFile(atPath: localURL.path, contents: Data())

        let store = SecurityScopedBookmarkStore()
        store.saveBookmark(for: self.tempDirectory)
        let service = PlaylistFileService(bookmarkStore: store)

        let tracks = await service.loadM3UPlaylist(from: playlistURL)
        XCTAssertEqual(tracks?.count, 1)
        XCTAssertEqual(tracks?.first?.url?.lastPathComponent, "local.wav")
    }
}

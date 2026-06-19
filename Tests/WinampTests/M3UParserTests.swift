@testable import Winamp
import XCTest

final class M3UParserTests: XCTestCase {
    private let playlistDir = URL(fileURLWithPath: "/tmp/playlists", isDirectory: true)

    func testSupportedExtensions() {
        XCTAssertTrue(M3UParser.isSupportedAudioExtension("mp3"))
        XCTAssertTrue(M3UParser.isSupportedAudioExtension("FLAC"))
        XCTAssertFalse(M3UParser.isSupportedAudioExtension("ogg"))
    }

    func testParseRelativeAndAbsolutePaths() {
        let content = """
        #EXTM3U
        # comment
        songs/one.mp3
        /absolute/two.flac
        file:///var/three.wav
        video.ogg
        """
        let urls = M3UParser.parseTrackURLs(from: content, playlistDirectory: self.playlistDir)
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0].lastPathComponent, "one.mp3")
        XCTAssertEqual(urls[1].path, "/absolute/two.flac")
        XCTAssertEqual(urls[2].path, "/var/three.wav")
    }

    func testParseFromFixtureFile() throws {
        let url = try XCTUnwrap(Bundle(for: M3UParserTests.self).url(forResource: "sample", withExtension: "m3u"))
        let content = try String(contentsOf: url, encoding: .utf8)
        let urls = M3UParser.parseTrackURLs(from: content, playlistDirectory: self.playlistDir)
        XCTAssertEqual(urls.map(\.lastPathComponent), [
            "relative-track.wav",
            "track.mp3",
            "absolute.flac",
        ])
    }

    func testParseRejectsParentDirectoryTraversal() {
        let content = """
        #EXTM3U
        ../outside.wav
        songs/ok.mp3
        deeply/../../escape.flac
        """
        let urls = M3UParser.parseTrackURLs(from: content, playlistDirectory: self.playlistDir)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].lastPathComponent, "ok.mp3")
        XCTAssertTrue(urls[0].path.hasSuffix("/songs/ok.mp3"))
    }

    func testResolveRelativeTrackURLAllowsSubdirectories() {
        let playlistDir = URL(fileURLWithPath: "/tmp/playlists/nested", isDirectory: true)
        let resolved = M3UParser.resolveRelativeTrackURL("artist/album/track.mp3", playlistDirectory: playlistDir)
        XCTAssertEqual(resolved?.path, "/tmp/playlists/nested/artist/album/track.mp3")
    }

    func testResolveRelativeTrackURLRejectsTraversal() {
        let playlistDir = URL(fileURLWithPath: "/tmp/playlists/nested", isDirectory: true)
        XCTAssertNil(M3UParser.resolveRelativeTrackURL("../outside.mp3", playlistDirectory: playlistDir))
        XCTAssertNil(M3UParser.resolveRelativeTrackURL("ok/../../outside.mp3", playlistDirectory: playlistDir))
    }
}

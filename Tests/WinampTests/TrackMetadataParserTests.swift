@testable import Winamp
import XCTest

final class TrackMetadataParserTests: XCTestCase {
    func testArtistDashTitlePattern() {
        let url = URL(fileURLWithPath: "/Music/Artist Name - Song Title.mp3")
        let parsed = TrackMetadataParser.parse(from: url)
        XCTAssertEqual(parsed.artist, "Artist Name")
        XCTAssertEqual(parsed.title, "Song Title")
    }

    func testTrackNumberPrefixRemoved() {
        let url = URL(fileURLWithPath: "/tmp/01 - Artist - Song Title.mp3")
        let parsed = TrackMetadataParser.parse(from: url)
        XCTAssertEqual(parsed.artist, "Artist")
        XCTAssertEqual(parsed.title, "Song Title")
    }

    func testSingleDashPattern() {
        let url = URL(fileURLWithPath: "/Music/Artist-Song Title.mp3")
        let parsed = TrackMetadataParser.parse(from: url)
        XCTAssertEqual(parsed.artist, "Artist")
        XCTAssertEqual(parsed.title, "Song Title")
    }

    func testDirectoryStructurePattern() {
        let url = URL(fileURLWithPath: "/Users/me/Music/Some Artist/Album/01 Track Name.mp3")
        let parsed = TrackMetadataParser.parse(from: url)
        XCTAssertEqual(parsed.artist, "Some Artist")
        XCTAssertEqual(parsed.title, "Track Name")
    }

    func testUnknownArtistFallback() {
        let url = URL(fileURLWithPath: "/standalone.mp3")
        let parsed = TrackMetadataParser.parse(from: url)
        XCTAssertEqual(parsed.artist, "Unknown Artist")
        XCTAssertEqual(parsed.title, "standalone")
    }
}

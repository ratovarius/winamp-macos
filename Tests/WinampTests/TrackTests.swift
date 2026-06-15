@testable import Winamp
import XCTest

final class TrackTests: XCTestCase {
    func testInitFromWAVFixtureReadsDurationAndFileSize() async throws {
        let url = try XCTUnwrap(
            Bundle(for: TrackTests.self).url(forResource: "short", withExtension: "wav")
        )
        let track = await Track.load(from: url)
        XCTAssertGreaterThan(track.duration, 0)
        XCTAssertGreaterThan(track.fileSize, 0)
        XCTAssertEqual(track.url, url)
        XCTAssertFalse(track.title.isEmpty)
    }

    func testInitFromURLUsesPathMetadataWhenTagsMissing() async {
        let url = URL(fileURLWithPath: "/Music/Artist Name - Song Title.mp3")
        let track = await Track.load(from: url)
        XCTAssertEqual(track.artist, "Artist Name")
        XCTAssertEqual(track.title, "Song Title")
    }

    func testFormattedDuration() {
        let track = Track(title: "T", artist: "A", duration: 125)
        XCTAssertEqual(track.formattedDuration, "2:05")
    }

    func testFormattedSizeUsesKBAndMB() {
        XCTAssertEqual(Track(title: "T", artist: "A", fileSize: 2048).formattedSize, "2 KB")
        XCTAssertEqual(Track(title: "T", artist: "A", fileSize: 2 * 1024 * 1024).formattedSize, "2.0 MB")
    }
}

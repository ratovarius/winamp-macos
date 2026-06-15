@testable import Winamp
import XCTest

final class LyricsParserTests: XCTestCase {
    func testParseLRCSingleTimestamp() {
        let lyrics = LyricsParser.parseLRC("[00:01.00]Hello world")
        XCTAssertEqual(lyrics.count, 1)
        XCTAssertEqual(lyrics[0].timestamp, 1.0, accuracy: 0.001)
        XCTAssertEqual(lyrics[0].text, "Hello world")
    }

    func testParseLRCMultipleTimestampsOnOneLine() {
        let lyrics = LyricsParser.parseLRC("[00:10.00][00:15.00]Chorus")
        XCTAssertEqual(lyrics.count, 2)
        XCTAssertEqual(lyrics[0].timestamp, 10.0, accuracy: 0.001)
        XCTAssertEqual(lyrics[1].timestamp, 15.0, accuracy: 0.001)
        XCTAssertEqual(lyrics[0].text, "Chorus")
        XCTAssertEqual(lyrics[1].text, "Chorus")
    }

    func testParseLRCSortsByTimestamp() {
        let content = """
        [00:30.00]Later
        [00:05.00]Earlier
        """
        let lyrics = LyricsParser.parseLRC(content)
        XCTAssertEqual(lyrics.map(\.timestamp), [5.0, 30.0])
    }

    func testParseLRCEmptyAndCommentLinesIgnored() {
        let content = """
        # not a lyric

        [00:01.00]Only line
        """
        let lyrics = LyricsParser.parseLRC(content)
        XCTAssertEqual(lyrics.count, 1)
        XCTAssertEqual(lyrics[0].text, "Only line")
    }

    func testParseLRCFromFixtureFile() throws {
        let url = try XCTUnwrap(Bundle(for: LyricsParserTests.self).url(forResource: "sample", withExtension: "lrc"))
        let content = try String(contentsOf: url, encoding: .utf8)
        let lyrics = LyricsParser.parseLRC(content)
        XCTAssertEqual(lyrics.count, 4)
        XCTAssertEqual(lyrics[0].text, "First line")
        XCTAssertEqual(lyrics[2].text, "Chorus line")
        XCTAssertEqual(lyrics[3].text, "Chorus line")
    }

    func testGetCurrentLyricBeforeFirstLine() {
        let lyrics = [
            LyricLine(timestamp: 5.0, text: "Five"),
            LyricLine(timestamp: 10.0, text: "Ten"),
        ]
        XCTAssertNil(LyricsParser.getCurrentLyric(lyrics: lyrics, currentTime: 2.0))
    }

    func testGetCurrentLyricAtBoundary() {
        let lyrics = [
            LyricLine(timestamp: 5.0, text: "Five"),
            LyricLine(timestamp: 10.0, text: "Ten"),
        ]
        XCTAssertEqual(LyricsParser.getCurrentLyric(lyrics: lyrics, currentTime: 5.0), "Five")
        XCTAssertEqual(LyricsParser.getCurrentLyric(lyrics: lyrics, currentTime: 9.9), "Five")
        XCTAssertEqual(LyricsParser.getCurrentLyric(lyrics: lyrics, currentTime: 10.0), "Ten")
    }

    func testFormatAsLRCRoundTrip() throws {
        let original = [
            LyricLine(timestamp: 65.5, text: "Minute five"),
            LyricLine(timestamp: 0.25, text: "Start"),
        ]
        let lrc = try XCTUnwrap(LyricsParser.formatAsLRC(original))
        let parsed = LyricsParser.parseLRC(lrc)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].text, "Start")
        XCTAssertEqual(parsed[1].text, "Minute five")
        XCTAssertEqual(parsed[0].timestamp, 0.25, accuracy: 0.02)
        XCTAssertEqual(parsed[1].timestamp, 65.5, accuracy: 0.02)
    }

    func testShouldFetchLyricsFromNetworkRequiresMetadata() {
        XCTAssertFalse(LyricsParser.shouldFetchLyricsFromNetwork(artist: "Unknown Artist", title: "Song", duration: 180))
        XCTAssertFalse(LyricsParser.shouldFetchLyricsFromNetwork(artist: "Artist", title: "", duration: 180))
        XCTAssertFalse(LyricsParser.shouldFetchLyricsFromNetwork(artist: "Artist", title: "Song", duration: 0))
        XCTAssertTrue(LyricsParser.shouldFetchLyricsFromNetwork(artist: "Artist", title: "Song", duration: 180))
    }

    func testLoadLyricsSkipsNetworkWhenMetadataInsufficient() {
        let completion = expectation(description: "lyrics completion")
        LyricsParser.loadLyrics(
            for: URL(fileURLWithPath: "/tmp/no-local-\(UUID().uuidString).mp3"),
            artist: "Unknown Artist",
            title: "Song",
            duration: 180
        ) { lyrics in
            XCTAssertNil(lyrics)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1.0)
    }
}

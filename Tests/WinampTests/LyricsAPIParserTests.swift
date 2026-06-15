@testable import Winamp
import XCTest

final class LyricsAPIParserTests: XCTestCase {
    func testParseAPIResponseWithSyncedLyrics() throws {
        let json = Data(
            """
            {"syncedLyrics":"[00:01.00]Hello\\n[00:05.00]World"}
            """.utf8
        )

        let lyrics = try XCTUnwrap(LyricsParser.parseAPIResponse(json))
        XCTAssertEqual(lyrics.count, 2)
        XCTAssertEqual(lyrics[0].text, "Hello")
        XCTAssertEqual(lyrics[1].text, "World")
    }

    func testParseAPIResponseMissingSyncedLyricsReturnsNil() {
        let json = Data(#"{"plainLyrics":"no timestamps"}"#.utf8)
        XCTAssertNil(LyricsParser.parseAPIResponse(json))
    }

    func testParseAPIResponseInvalidJSONReturnsNil() {
        XCTAssertNil(LyricsParser.parseAPIResponse(Data("not json".utf8)))
    }
}

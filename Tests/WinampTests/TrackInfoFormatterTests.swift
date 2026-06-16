@testable import Winamp
import XCTest

final class TrackInfoFormatterTests: XCTestCase {
    func testSummaryIncludesPathAndDuration() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("info-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let track = Track(
            title: "Song",
            artist: "Artist",
            duration: 125,
            fileSize: 4096,
            url: fileURL
        )

        let summary = TrackInfoFormatter.summary(for: track)
        XCTAssertTrue(summary.contains(fileURL.path))
        XCTAssertTrue(summary.contains("2:05"))
        XCTAssertTrue(summary.contains("4 KB"))
    }
}

@testable import Winamp
import XCTest

final class FileSystemHelpersTests: XCTestCase {
    func testLocalPathIsNotNetworkVolume() {
        XCTAssertFalse(FileSystemHelpers.isNetworkVolume(URL(fileURLWithPath: "/tmp/example.mp3")))
    }

    func testVolumesPathFallbackTreatedAsNetwork() {
        XCTAssertTrue(FileSystemHelpers.isNetworkVolume(URL(fileURLWithPath: "/Volumes/ExampleShare/track.mp3")))
    }
}

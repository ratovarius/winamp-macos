import MediaPlayer
@testable import Winamp
import XCTest

final class NowPlayingInfoTests: XCTestCase {
    private func makeInfo(isPlaying: Bool) -> NowPlayingInfo {
        NowPlayingInfo(
            title: "Song",
            artist: "Artist",
            duration: 200,
            elapsedTime: 42,
            isPlaying: isPlaying
        )
    }

    func testPlaybackRateIsOneWhilePlaying() {
        XCTAssertEqual(self.makeInfo(isPlaying: true).playbackRate, 1.0)
    }

    func testPlaybackRateIsZeroWhilePaused() {
        XCTAssertEqual(self.makeInfo(isPlaying: false).playbackRate, 0.0)
    }

    func testDictionaryMapsAllFieldsToMediaPlayerKeys() {
        let dict = self.makeInfo(isPlaying: true).dictionary
        XCTAssertEqual(dict[MPMediaItemPropertyTitle] as? String, "Song")
        XCTAssertEqual(dict[MPMediaItemPropertyArtist] as? String, "Artist")
        XCTAssertEqual(dict[MPMediaItemPropertyPlaybackDuration] as? TimeInterval, 200)
        XCTAssertEqual(dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval, 42)
        XCTAssertEqual(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0)
    }

    func testDictionaryReflectsPausedRate() {
        let dict = self.makeInfo(isPlaying: false).dictionary
        XCTAssertEqual(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0)
    }

    func testEquatableComparesStoredFields() {
        XCTAssertEqual(self.makeInfo(isPlaying: true), self.makeInfo(isPlaying: true))
        XCTAssertNotEqual(self.makeInfo(isPlaying: true), self.makeInfo(isPlaying: false))
    }
}

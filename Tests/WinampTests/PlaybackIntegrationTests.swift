@testable import Winamp
import XCTest

@MainActor
final class PlaybackIntegrationTests: XCTestCase {
    private var player: AudioPlayer!
    private var manager: PlaylistManager!
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        self.player = AudioPlayer(installRemoteCommands: false)
        self.manager = PlaylistManager(audioPlayer: self.player, restoreBookmarks: false, restorePlaylist: false)
        self.player.onTrackFinished = { [weak manager] in
            manager?.next()
        }
        self.fixtureURL = try XCTUnwrap(
            Bundle(for: PlaybackIntegrationTests.self).url(forResource: "short", withExtension: "wav")
        )
    }

    func testTrackCompletionAdvancesToNextTrack() {
        self.manager.tracks = [
            Track(title: "First", artist: "Test", url: self.fixtureURL),
            Track(title: "Second", artist: "Test", url: self.fixtureURL),
        ]
        self.manager.currentIndex = 0
        XCTAssertTrue(self.waitForLoad(self.manager.tracks[0]))
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertEqual(self.player.currentTrack?.title, "First")

        self.player.testing_markAsPlayingForTests()
        self.player.testing_simulateTrackCompletion()
        waitForMainQueue(after: 0.5)

        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.player.currentTrack?.title, "Second")
    }

    func testTrackCompletionDoesNotAdvanceAfterStop() {
        let finishedCount = SendableBox(0)
        self.player.onTrackFinished = { finishedCount.value += 1 }

        let track = Track(title: "Only", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_markAsPlayingForTests()
        self.player.stop()

        let stopExpectation = expectation(description: "stop processed")
        self.player.testing_afterAudioQueueFlush {
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)

        self.player.testing_simulateTrackCompletion()
        waitForMainQueue()

        XCTAssertEqual(finishedCount.value, 0)
    }

    func testOnTrackFinishedInvokedWhenAutoAdvanceEnabled() {
        let finishedCount = SendableBox(0)
        self.player.onTrackFinished = { finishedCount.value += 1 }

        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_markAsPlayingForTests()
        self.player.testing_simulateTrackCompletion()
        waitForMainQueue()

        XCTAssertEqual(finishedCount.value, 1)
    }

    private func waitForLoad(_ track: Track, timeout: TimeInterval = 5.0) -> Bool {
        let loadExpectation = expectation(description: "load-\(UUID().uuidString)")
        let outcome = SendableBox(false)
        self.player.loadTrack(track) { loaded in
            outcome.value = loaded
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: timeout)
        return outcome.value
    }
}

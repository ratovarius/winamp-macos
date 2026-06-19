@testable import Winamp
import XCTest

@MainActor
final class MockAudioPlayer: AudioPlaybackControlling {
    var loadTrackCalls: [Track] = []
    var playCallCount = 0
    var stopCallCount = 0
    var loadShouldSucceed = true
    var loadCompletionDelay: TimeInterval = 0
    private(set) var lastLoadCompletion: Bool?

    func loadTrack(_ track: Track, completion: (@MainActor @Sendable (Bool) -> Void)?) {
        self.loadTrackCalls.append(track)
        let succeed = self.loadShouldSucceed
        let deliver = {
            self.lastLoadCompletion = succeed
            completion?(succeed)
        }
        if self.loadCompletionDelay > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(self.loadCompletionDelay * 1_000_000_000))
                deliver()
            }
        } else {
            deliver()
        }
    }

    func play() {
        self.playCallCount += 1
    }

    func stop() {
        self.stopCallCount += 1
    }

    func seek(to _: TimeInterval) {}
}

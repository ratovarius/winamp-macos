import Foundation
import MediaPlayer

/// The lock-screen / Control Center "Now Playing" snapshot, built as a pure value from the
/// current track and playback state.
///
/// Separated from `AudioPlayer` so the mapping to the `MPNowPlayingInfoCenter` dictionary is
/// unit-testable without driving the audio engine — mirroring the `VolumeModel` pattern.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var duration: TimeInterval
    var elapsedTime: TimeInterval
    var isPlaying: Bool

    /// Playback rate the lock screen shows: 1.0 while playing, 0.0 when paused/stopped.
    var playbackRate: Double {
        self.isPlaying ? 1.0 : 0.0
    }

    /// The `MPNowPlayingInfoCenter.nowPlayingInfo` dictionary representation.
    var dictionary: [String: Any] {
        [
            MPMediaItemPropertyTitle: self.title,
            MPMediaItemPropertyArtist: self.artist,
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: self.playbackRate,
        ]
    }
}

import Foundation

/// Transport surface used by `PlaylistManager` and test doubles.
/// UI and EQ/visualizer code may call `AudioPlayer` directly for richer playback state.
@MainActor
protocol AudioPlaybackControlling: AnyObject {
    func loadTrack(_ track: Track, completion: (@MainActor @Sendable (Bool) -> Void)?)
    func play()
    func stop()
    func seek(to time: TimeInterval)
}

extension AudioPlayer: AudioPlaybackControlling {}

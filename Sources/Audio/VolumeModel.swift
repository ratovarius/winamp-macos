import Foundation

/// Pure volume math extracted from `AudioPlayer`: the perceptual fader taper and how it
/// combines with ReplayGain normalization into the linear gain applied to the player node.
///
/// Kept stateless and free of audio-engine types so the mapping is unit-testable without an
/// `AVAudioEngine`.
enum VolumeModel {
    /// Highest linear gain the player node may reach. Matches the ReplayGain boost ceiling so a
    /// normalization boost on top of a loud fader position can't run away.
    static let maxAppliedGain: Float = 4

    /// Maps the linear 0…1 slider position to an amplitude using an audio (perceptual) taper.
    ///
    /// A 1:1 slider→amplitude mapping crowds almost all perceived loudness change into the bottom
    /// of the travel. Real faders use a curve that's roughly logarithmic in loudness; a cubic
    /// taper (`position³`) is the common, cheap approximation — full-scale at 1.0, ~−18 dB at the
    /// halfway point — so the slider feels even across its range.
    static func taper(_ position: Float) -> Float {
        let p = max(0, min(1, position))
        return p * p * p
    }

    /// The linear gain to apply to the player node for a tapered slider position and a linear
    /// normalization gain, clamped to `0…maxAppliedGain`.
    static func appliedGain(position: Float, normalizationGain: Float) -> Float {
        max(0, min(self.maxAppliedGain, self.taper(position) * normalizationGain))
    }

    /// Convenience overload that resolves the normalization gain from a `ReplayGain` tag set
    /// (or unity when normalization is disabled) before combining it with the tapered position.
    static func appliedGain(
        position: Float,
        normalizationEnabled: Bool,
        replayGain: ReplayGain,
        preferAlbum: Bool
    ) -> Float {
        let normalization = normalizationEnabled
            ? replayGain.normalizationGain(preferAlbum: preferAlbum)
            : 1
        return self.appliedGain(position: position, normalizationGain: normalization)
    }
}

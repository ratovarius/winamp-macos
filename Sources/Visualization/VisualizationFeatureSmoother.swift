import Foundation

/// Display-rate attack/release smoothing for spectrum bands (decoupled from audio callback rate).
struct VisualizationFeatureSmoother {
    private static let attackRate: Float = 110
    private static let releaseRate: Float = 16

    private var smoothedSpectrum = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)

    /// Advances the smoothing state and returns it.
    ///
    /// The returned array *is* the smoother's own state storage, handed back value-semantically
    /// via copy-on-write: a caller that consumes it within the frame (the render path) incurs no
    /// per-frame allocation, while any caller that retains it past the next `update` still sees an
    /// unchanged snapshot (the next mutation copies). Saves one `[Float]` allocation per frame.
    mutating func update(targets: [Float], isPlaying: Bool, deltaTime: Float) -> [Float] {
        let clampedDelta = min(max(deltaTime, 0), 0.1)

        for index in 0 ..< AudioFeatures.spectrumBandCount {
            let target = isPlaying ? targets[index] : 0
            let current = self.smoothedSpectrum[index]
            let rate = target >= current ? Self.attackRate : Self.releaseRate
            let step = min(1, clampedDelta * rate)
            self.smoothedSpectrum[index] = current + (target - current) * step
        }

        return self.smoothedSpectrum
    }
}

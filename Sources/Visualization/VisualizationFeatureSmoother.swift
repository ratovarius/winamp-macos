import Foundation

/// Display-rate attack/release smoothing for spectrum bands (decoupled from audio callback rate).
struct VisualizationFeatureSmoother: Sendable {
    private static let attackRate: Float = 110
    private static let releaseRate: Float = 16

    private var smoothedSpectrum = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)

    mutating func update(targets: [Float], isPlaying: Bool, deltaTime: Float) -> [Float] {
        let clampedDelta = min(max(deltaTime, 0), 0.1)
        var output = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)

        for index in 0 ..< AudioFeatures.spectrumBandCount {
            let target = isPlaying ? targets[index] : 0
            let current = self.smoothedSpectrum[index]
            let rate = target >= current ? Self.attackRate : Self.releaseRate
            let step = min(1, clampedDelta * rate)
            self.smoothedSpectrum[index] = current + (target - current) * step
            output[index] = self.smoothedSpectrum[index]
        }

        return output
    }
}

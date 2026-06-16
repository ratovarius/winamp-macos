import Foundation

/// Per-band bar falloff and peak-hold lines matching classic Winamp / Webamp analyzer behavior.
struct SpectrumPeakTracker {
    private static let maxBarHeight: Float = 15
    private static let barFalloffRate: Float = 12.0 / 16.0
    private static let peakInitialStep: Float = 3.0
    private static let peakStepGrowth: Float = 1.1

    private var barLevels = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)
    private var peakScaled = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)
    private var peakStep = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)
    /// Reused scratch for the per-frame peak output (see `update`'s value-semantics note).
    private var peaksOut = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)

    mutating func reset() {
        self.barLevels = Array(repeating: 0, count: AudioFeatures.spectrumBandCount)
        self.peakScaled = Array(repeating: 0, count: AudioFeatures.spectrumBandCount)
        self.peakStep = Array(repeating: 0, count: AudioFeatures.spectrumBandCount)
    }

    mutating func update(
        targets: [Float],
        isPlaying: Bool,
        deltaTime: Float
    ) -> (bars: [Float], peaks: [Float]) {
        let frameScale = min(max(deltaTime * 60, 0), 4)
        let barFalloff = (Self.barFalloffRate / Self.maxBarHeight) * frameScale

        for index in 0 ..< AudioFeatures.spectrumBandCount {
            let target = isPlaying ? min(max(targets[index], 0), 1) : 0

            self.barLevels[index] -= barFalloff
            if self.barLevels[index] <= target {
                self.barLevels[index] = target
            }

            let scaledBar = self.barLevels[index] * Self.maxBarHeight * 256
            if self.peakScaled[index] <= scaledBar {
                self.peakScaled[index] = scaledBar
                self.peakStep[index] = Self.peakInitialStep
            }

            self.peakScaled[index] -= round(self.peakStep[index] * frameScale)
            self.peakStep[index] *= pow(Self.peakStepGrowth, frameScale)

            if self.peakScaled[index] <= 0 {
                self.peakScaled[index] = 0
            }

            self.peaksOut[index] = (self.peakScaled[index] / 256) / Self.maxBarHeight
        }

        // `barLevels` already holds the bar output and `peaksOut` is reused scratch; both are returned
        // value-semantically (copy-on-write), so the render path avoids two `[Float]` allocations per
        // frame while a caller that retains a result still sees a stable snapshot.
        return (self.barLevels, self.peaksOut)
    }
}

import Foundation

/// Thread-safe snapshot of audio analysis data for the visualization render loop.
struct AudioFeatures: Sendable {
    static let spectrumBandCount = 32
    static let fftSize = 1024
    static let fftHopSize = 256
    static let waveformSampleCount = 256
    /// Time-domain samples fed into the scope (Webamp uses 576 of its 1024-point FFT window).
    static let scopeWaveformSampleCount = 2048

    static func scopeColumnCount(forWidth width: CGFloat) -> Int {
        let pixelColumns = Int(width.rounded(.up))
        return min(max(pixelColumns, 120), 512)
    }

    var spectrum: [Float]
    var waveformLeft: [Float]
    var waveformRight: [Float]
    var isPlaying: Bool

    static let zero = AudioFeatures(
        spectrum: Array(repeating: 0, count: spectrumBandCount),
        waveformLeft: Array(repeating: 0, count: waveformSampleCount),
        waveformRight: Array(repeating: 0, count: waveformSampleCount),
        isPlaying: false
    )

    var bassEnergy: Float {
        Self.average(self.spectrum.prefix(6))
    }

    var midEnergy: Float {
        Self.average(self.spectrum.dropFirst(6).prefix(12))
    }

    var trebleEnergy: Float {
        Self.average(self.spectrum.suffix(14))
    }

    var overallEnergy: Float {
        Self.average(self.spectrum)
    }

    private static func average(_ values: some Collection<Float>) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }
}

/// Raw audio analysis targets + waveform ring buffer for the Metal render loop.
final class AudioFeatureBus: @unchecked Sendable {
    static let shared = AudioFeatureBus()

    let waveformRing = WaveformRingBuffer()

    private let lock = NSLock()
    private var spectrumTargets = Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)
    private var isPlaying = false

    private init() {}

    /// Publishes raw FFT band targets from the audio analysis path (no smoothing).
    func publishSpectrum(_ spectrum: [Float], isPlaying: Bool) {
        self.lock.lock()
        self.spectrumTargets = Self.normalizedSpectrum(spectrum)
        self.isPlaying = isPlaying
        self.lock.unlock()
    }

    func setPlaying(_ isPlaying: Bool) {
        self.lock.lock()
        self.isPlaying = isPlaying
        self.lock.unlock()
    }

    func spectrumSnapshot() -> (targets: [Float], isPlaying: Bool) {
        self.lock.lock()
        let copy = (self.spectrumTargets, self.isPlaying)
        self.lock.unlock()
        return copy
    }

    /// Builds a display snapshot: resamples waveform ring + returns raw spectrum targets.
    /// Spectrum smoothing happens in `MetalVisualizationRenderer` at display rate.
    func snapshot(waveformSampleCount: Int = AudioFeatures.waveformSampleCount) -> AudioFeatures {
        let (targets, playing) = self.spectrumSnapshot()
        let waveform = self.waveformRing.readResampled(count: waveformSampleCount)
        return AudioFeatures(
            spectrum: targets,
            waveformLeft: waveform.left,
            waveformRight: waveform.right,
            isPlaying: playing
        )
    }

    private static func normalizedSpectrum(_ values: [Float]) -> [Float] {
        var result = Array(values.prefix(AudioFeatures.spectrumBandCount))
        if result.count < AudioFeatures.spectrumBandCount {
            result.append(contentsOf: Array(repeating: 0, count: AudioFeatures.spectrumBandCount - result.count))
        }
        return result
    }
}

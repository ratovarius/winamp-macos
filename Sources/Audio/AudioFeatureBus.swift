import Foundation
import QuartzCore

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
    /// Intra-buffer FFT hop-frames from the most recent audio tap buffer. The tap
    /// only fires ~10×/s (100 ms buffers), so a single frame per buffer makes the
    /// spectrum step at 10 Hz. Storing every hop and playing them out by elapsed
    /// time (see `VisualizationPlayoutClock`) lets the display loop sample fresh
    /// detail every frame.
    private var spectrumFrames: [[Float]] = [Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)]
    private var spectrumBatchArrival: Double = 0
    private var spectrumBatchDuration: Double = 0
    private var isPlaying = false

    private init() {}

    /// Publishes the FFT hop-frames of one audio buffer (no smoothing), tagged with
    /// the wall-clock arrival time and how long the buffer spans so the consumer can
    /// pace them out across the buffer's duration.
    func publishSpectrumFrames(
        _ frames: [[Float]],
        arrivalTime: Double,
        batchDuration: Double,
        isPlaying: Bool
    ) {
        let normalized = frames.isEmpty
            ? [Array(repeating: Float(0), count: AudioFeatures.spectrumBandCount)]
            : frames.map(Self.normalizedSpectrum)
        self.lock.lock()
        self.spectrumFrames = normalized
        self.spectrumBatchArrival = arrivalTime
        self.spectrumBatchDuration = batchDuration
        self.isPlaying = isPlaying
        self.lock.unlock()
    }

    /// Publishes a single spectrum frame (no intra-buffer detail). Convenience used
    /// by tests and any single-shot path; always reads back as the newest frame.
    func publishSpectrum(_ spectrum: [Float], isPlaying: Bool) {
        self.publishSpectrumFrames([spectrum], arrivalTime: 0, batchDuration: 0, isPlaying: isPlaying)
    }

    func setPlaying(_ isPlaying: Bool) {
        self.lock.lock()
        self.isPlaying = isPlaying
        self.lock.unlock()
    }

    /// Returns the paced spectrum frame for the given display time plus the play state.
    func spectrumSnapshot(at now: Double) -> (targets: [Float], isPlaying: Bool) {
        self.lock.lock()
        let index = VisualizationPlayoutClock.frameIndex(
            now: now,
            batchArrival: self.spectrumBatchArrival,
            frameCount: self.spectrumFrames.count,
            batchDuration: self.spectrumBatchDuration
        )
        let targets = self.spectrumFrames[index]
        let playing = self.isPlaying
        self.lock.unlock()
        return (targets, playing)
    }

    /// Convenience snapshot at the current media time (used by tests).
    func spectrumSnapshot() -> (targets: [Float], isPlaying: Bool) {
        self.spectrumSnapshot(at: CACurrentMediaTime())
    }

    /// Builds a display snapshot: resamples waveform ring + returns the paced spectrum.
    /// Spectrum smoothing happens in `MetalVisualizationRenderer` at display rate.
    func snapshot(
        at now: Double = CACurrentMediaTime(),
        waveformSampleCount: Int = AudioFeatures.waveformSampleCount
    ) -> AudioFeatures {
        let (targets, playing) = self.spectrumSnapshot(at: now)
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

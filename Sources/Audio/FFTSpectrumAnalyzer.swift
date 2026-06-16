import Accelerate
@preconcurrency import AVFoundation
import Foundation

final class FFTSpectrumAnalyzer: @unchecked Sendable {
    let bandCount: Int
    private let fftSize: Int
    private let hopSize: Int
    private let log2n: vDSP_Length
    private var fftSetup: FFTSetup?
    private var window: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudes: [Float]
    // Reusable per-hop scratch. Like `realBuffer`/`imagBuffer`/`magnitudes`, these are only
    // touched on `processingQueue` (serial), so the bars/FFT path allocates nothing per hop.
    private var windowScratch: [Float]
    private var windowedScratch: [Float]
    private var bandMappings: [(start: Int, end: Int)] = []
    private var lastSampleRate: Float = 0
    private let processingQueue = DispatchQueue(label: "com.winamp.fft", qos: .userInteractive)

    private var windowRing = [Float](repeating: 0, count: AudioFeatures.fftSize)
    private var ringWriteIndex = 0
    private var samplesUntilFFT = 0

    var onSpectrumUpdate: (@Sendable ([Float]) -> Void)?
    var onWaveformUpdate: (@Sendable ([Float], [Float]) -> Void)?
    var onAnalysisUpdate: (@Sendable (_ bands: [Float], _ left: [Float], _ right: [Float]) -> Void)?
    /// All FFT hop-frames computed from one audio buffer, plus how long that buffer
    /// spans in seconds, so the consumer can play the frames out across the buffer's
    /// duration instead of showing only the last hop (which steps at the tap rate).
    var onSpectrumFrames: (@Sendable (_ frames: [[Float]], _ batchDuration: Double) -> Void)?
    let waveformChunkSize: Int

    init(
        bandCount: Int = AudioFeatures.spectrumBandCount,
        fftSize: Int = AudioFeatures.fftSize,
        hopSize: Int = AudioFeatures.fftHopSize,
        waveformChunkSize: Int = 32
    ) {
        self.bandCount = bandCount
        self.fftSize = fftSize
        self.hopSize = max(1, min(hopSize, fftSize))
        self.waveformChunkSize = waveformChunkSize
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.window = [Float](repeating: 0, count: fftSize)
        self.realBuffer = [Float](repeating: 0, count: fftSize / 2)
        self.imagBuffer = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.windowScratch = [Float](repeating: 0, count: fftSize)
        self.windowedScratch = [Float](repeating: 0, count: fftSize)
        self.fftSetup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&self.window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.prepareBandMappings(sampleRate: 44100)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func installTap(on node: AVAudioNode) {
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        node.installTap(onBus: 0, bufferSize: AVAudioFrameCount(self.hopSize), format: format) { [weak self] buffer, _ in
            Self.measureTapRate(frameLength: Int(buffer.frameLength), sampleRate: format.sampleRate)
            self?.enqueue(buffer: buffer)
        }
    }

    // TEMP-DIAGNOSTIC: measure the real tap buffer size + callback rate.
    private nonisolated(unsafe) static var tapMeasureCount = 0
    private nonisolated(unsafe) static var tapMeasureStart = CFAbsoluteTimeGetCurrent()
    private static let tapMeasureLock = NSLock()
    private static func measureTapRate(frameLength: Int, sampleRate: Double) {
        tapMeasureLock.lock()
        defer { tapMeasureLock.unlock() }
        tapMeasureCount += 1
        if tapMeasureCount % 30 == 0 {
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - tapMeasureStart
            let hz = Double(30) / max(elapsed, 0.000_1)
            print(String(format: "[TAP-DIAG] frameLength=%d sampleRate=%.0f → callbackRate=%.1f Hz (buffer spans %.1f ms)",
                         frameLength, sampleRate, hz, Double(frameLength) / sampleRate * 1000))
            fflush(stdout)
            tapMeasureStart = now
        }
    }

    func removeTap(from node: AVAudioNode) {
        node.removeTap(onBus: 0)
    }

    private func enqueue(buffer: AVAudioPCMBuffer) {
        guard let copy = copyBuffer(buffer) else { return }
        self.processingQueue.async { [weak self] in
            guard let self else { return }
            AudioFeatureBus.shared.waveformRing.append(pcm: copy)
            let waveform = self.extractWaveformSamples(from: copy, sampleCount: self.waveformChunkSize)
            var frames: [[Float]] = []
            let bands: [Float]
            if let streamed = self.analyzeStreaming(copy, onHop: { hopBands in
                frames.append(hopBands)
                self.onSpectrumUpdate?(hopBands)
            }) {
                bands = streamed
            } else {
                bands = self.analyze(copy)
                frames.append(bands)
                self.onSpectrumUpdate?(bands)
            }
            let sampleRate = copy.format.sampleRate
            let batchDuration = sampleRate > 0 ? Double(copy.frameLength) / sampleRate : 0
            self.onSpectrumFrames?(frames, batchDuration)
            self.onAnalysisUpdate?(bands, waveform.left, waveform.right)
            self.onWaveformUpdate?(waveform.left, waveform.right)
        }
    }

    /// Exercises the tap processing path without installing an AVAudioNode tap.
    func processBufferForTests(_ buffer: AVAudioPCMBuffer) {
        self.enqueue(buffer: buffer)
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        guard let src = buffer.floatChannelData, let dst = copy.floatChannelData else {
            return nil
        }
        let frames = Int(buffer.frameLength)
        for channel in 0 ..< channels {
            memcpy(dst[channel], src[channel], frames * MemoryLayout<Float>.size)
        }
        return copy
    }

    private func prepareBandMappings(sampleRate: Float) {
        let minFreq: Float = 60
        let maxFreq = max(minFreq + 1, sampleRate * 0.5)
        self.bandMappings = (0 ..< self.bandCount).map { band in
            let t0 = Float(band) / Float(self.bandCount)
            let t1 = Float(band + 1) / Float(self.bandCount)
            let f0 = minFreq * pow(maxFreq / minFreq, t0)
            let f1 = minFreq * pow(maxFreq / minFreq, t1)
            let bin0 = max(1, Int(f0 * Float(self.fftSize) / sampleRate))
            let bin1 = max(bin0 + 1, Int(f1 * Float(self.fftSize) / sampleRate))
            return (start: bin0, end: min(bin1, self.fftSize / 2))
        }
        self.lastSampleRate = sampleRate
    }

    /// Single-window analysis for tests and short buffers.
    func analyze(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let mono = self.makeMonoSamples(from: buffer) else {
            return Array(repeating: 0, count: self.bandCount)
        }

        var window = Array(repeating: Float(0), count: self.fftSize)
        let sampleCount = min(mono.count, self.fftSize)
        if sampleCount == self.fftSize {
            window = mono
        } else {
            window.replaceSubrange(0 ..< sampleCount, with: mono.prefix(sampleCount))
        }

        return self.bands(fromWindow: window, sampleRate: Float(buffer.format.sampleRate))
    }

    private func analyzeStreaming(
        _ buffer: AVAudioPCMBuffer,
        onHop: (([Float]) -> Void)? = nil
    ) -> [Float]? {
        guard let mono = self.makeMonoSamples(from: buffer) else { return nil }

        var latestBands: [Float]?
        for sample in mono {
            self.windowRing[self.ringWriteIndex] = sample
            self.ringWriteIndex = (self.ringWriteIndex + 1) % self.fftSize
            self.samplesUntilFFT += 1

            if self.samplesUntilFFT >= self.hopSize {
                self.samplesUntilFFT = 0
                let bands = self.bands(
                    fromWindow: self.linearizedWindow(),
                    sampleRate: Float(buffer.format.sampleRate)
                )
                latestBands = bands
                onHop?(bands)
            }
        }
        return latestBands
    }

    private func linearizedWindow() -> [Float] {
        for index in 0 ..< self.fftSize {
            self.windowScratch[index] = self.windowRing[(self.ringWriteIndex + index) % self.fftSize]
        }
        return self.windowScratch
    }

    private func makeMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let channels = Int(buffer.format.channelCount)
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        var mono = [Float](repeating: 0, count: frameLength)
        for index in 0 ..< frameLength {
            var sum: Float = 0
            for channel in 0 ..< channels {
                sum += channelData[channel][index]
            }
            mono[index] = sum / Float(channels)
        }
        return mono
    }

    private func bands(fromWindow windowSamples: [Float], sampleRate: Float) -> [Float] {
        guard let fftSetup else {
            return Array(repeating: 0, count: self.bandCount)
        }

        if self.bandMappings.isEmpty || abs(sampleRate - self.lastSampleRate) > 1 {
            self.prepareBandMappings(sampleRate: sampleRate)
        }

        guard windowSamples.count == self.fftSize else { return Array(repeating: 0, count: self.bandCount) }

        // Window directly into reusable scratch (was: copy the input, then window in place
        // — one fftSize allocation per hop).
        vDSP_vmul(windowSamples, 1, self.window, 1, &self.windowedScratch, 1, vDSP_Length(self.fftSize))

        self.realBuffer.withUnsafeMutableBufferPointer { realPtr in
            self.imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else {
                    return
                }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                self.windowedScratch.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.bindMemory(to: DSPComplex.self).baseAddress else {
                        return
                    }
                    vDSP_ctoz(baseAddress, 2, &splitComplex, 1, vDSP_Length(self.fftSize / 2))
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &self.magnitudes, 1, vDSP_Length(self.fftSize / 2))
            }
        }

        var bands = [Float](repeating: 0, count: bandCount)
        for (index, mapping) in self.bandMappings.enumerated() {
            let slice = self.magnitudes[mapping.start ..< mapping.end]
            let peak = slice.max() ?? 0
            let meanSquare = slice.reduce(0) { $0 + $1 * $1 } / Float(max(slice.count, 1))
            let rms = sqrt(meanSquare)
            let combined = peak * 0.55 + rms * 0.45
            bands[index] = self.normalizedMagnitude(combined)
        }

        return bands
    }

    func extractWaveformSamples(from buffer: AVAudioPCMBuffer, sampleCount: Int) -> (left: [Float], right: [Float]) {
        self.extractRecentWaveformSamples(from: buffer, sampleCount: sampleCount)
    }

    /// Uses the most recent frames so the scope reacts immediately to the audio tap.
    func extractRecentWaveformSamples(from buffer: AVAudioPCMBuffer, sampleCount: Int) -> (left: [Float], right: [Float]) {
        guard let channelData = buffer.floatChannelData else {
            return ([], [])
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, sampleCount > 0 else {
            return ([], [])
        }

        let channels = Int(buffer.format.channelCount)
        var left = [Float](repeating: 0, count: sampleCount)
        var right = [Float](repeating: 0, count: sampleCount)

        let available = min(frameLength, sampleCount)
        let start = frameLength - available

        for index in 0 ..< available {
            let frame = start + index
            if channels == 1 {
                let sample = channelData[0][frame]
                left[index + (sampleCount - available)] = sample
                right[index + (sampleCount - available)] = sample
            } else {
                left[index + (sampleCount - available)] = channelData[0][frame]
                right[index + (sampleCount - available)] = channelData[1][frame]
            }
        }

        return (left, right)
    }

    func extractAveragedWaveformSamples(from buffer: AVAudioPCMBuffer, sampleCount: Int) -> (left: [Float], right: [Float]) {
        guard let channelData = buffer.floatChannelData else {
            return ([], [])
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, sampleCount > 0 else {
            return ([], [])
        }

        let channels = Int(buffer.format.channelCount)
        var left = [Float](repeating: 0, count: sampleCount)
        var right = [Float](repeating: 0, count: sampleCount)

        for index in 0 ..< sampleCount {
            let start = (index * frameLength) / sampleCount
            let end = min(frameLength, ((index + 1) * frameLength) / sampleCount)
            guard end > start else { continue }

            var leftSum: Float = 0
            var rightSum: Float = 0
            let sampleSpan = Float(end - start)

            if channels == 1 {
                for frame in start ..< end {
                    let sample = channelData[0][frame]
                    leftSum += sample
                    rightSum += sample
                }
            } else {
                for frame in start ..< end {
                    leftSum += channelData[0][frame]
                    rightSum += channelData[1][frame]
                }
            }

            left[index] = leftSum / sampleSpan
            right[index] = rightSum / sampleSpan
        }

        return (left, right)
    }

    private func normalizedMagnitude(_ magnitude: Float) -> Float {
        guard magnitude > 0 else { return 0 }
        let decibels = 10 * log10(magnitude)
        let floor: Float = -60
        // Headroom above the raw 0 dB reference so peak bins are not always clipped to 1.0.
        let ceiling: Float = 18
        let clamped = min(max(decibels, floor), ceiling)
        return (clamped - floor) / (ceiling - floor)
    }
}

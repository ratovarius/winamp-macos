import AVFoundation
import XCTest

@testable import Winamp

final class FFTSpectrumAnalyzerTests: XCTestCase {
    func testSilenceProducesZeroBands() {
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024)
        let buffer = self.makeBuffer(samples: Array(repeating: 0, count: 1024))
        let bands = analyzer.analyze(buffer)
        XCTAssertEqual(bands.count, AudioFeatures.spectrumBandCount)
        XCTAssertTrue(bands.allSatisfy { $0 < 0.05 })
    }

    func testWeakerSignalProducesLowerBandsThanStrongerSignal() {
        let sampleRate: Double = 44100
        let frequency: Double = 440
        let frameCount = 1024

        let loudSamples = (0 ..< frameCount).map { index in
            Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
        let quietSamples = loudSamples.map { $0 * 0.08 }

        let loudAnalyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: frameCount)
        let quietAnalyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: frameCount)

        let loudBands = loudAnalyzer.analyze(self.makeBuffer(samples: loudSamples, sampleRate: sampleRate))
        let quietBands = quietAnalyzer.analyze(self.makeBuffer(samples: quietSamples, sampleRate: sampleRate))

        let loudEnergy = loudBands.reduce(0, +)
        let quietEnergy = quietBands.reduce(0, +)
        XCTAssertGreaterThan(loudEnergy, quietEnergy * 1.2)
    }

    func testSineWaveProducesNonZeroEnergy() {
        let sampleRate: Double = 44100
        let frequency: Double = 440
        let samples = (0 ..< 1024).map { index in
            Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024)
        let buffer = self.makeBuffer(samples: samples, sampleRate: sampleRate)
        let bands = analyzer.analyze(buffer)
        XCTAssertGreaterThan(bands.max() ?? 0, 0.2)
    }

    func testOverlappingHopProducesMultipleUpdates() {
        let analyzer = FFTSpectrumAnalyzer(
            bandCount: AudioFeatures.spectrumBandCount,
            fftSize: 1024,
            hopSize: 512
        )
        let buffer = self.makeBuffer(samples: Array(repeating: 0.35, count: 1024))
        let updateExpectation = expectation(description: "spectrum update")
        updateExpectation.expectedFulfillmentCount = 2

        analyzer.onSpectrumUpdate = { bands in
            XCTAssertEqual(bands.count, AudioFeatures.spectrumBandCount)
            updateExpectation.fulfill()
        }

        analyzer.processBufferForTests(buffer)
        wait(for: [updateExpectation], timeout: 2.0)
    }

    func testOnSpectrumUpdateFiresAfterAsyncProcessing() {
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024)
        let buffer = self.makeBuffer(samples: Array(repeating: 0.5, count: 1024))
        let updateExpectation = expectation(description: "spectrum update")
        let fulfilled = SendableBox(false)

        analyzer.onSpectrumUpdate = { bands in
            XCTAssertEqual(bands.count, AudioFeatures.spectrumBandCount)
            guard !fulfilled.value else { return }
            fulfilled.value = true
            updateExpectation.fulfill()
        }

        analyzer.processBufferForTests(buffer)
        wait(for: [updateExpectation], timeout: 2.0)
    }

    func testExtractWaveformSamplesFromConstantSignal() {
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024, waveformChunkSize: 16)
        let buffer = self.makeBuffer(samples: Array(repeating: 0.5, count: 1024))
        let waveform = analyzer.extractWaveformSamples(from: buffer, sampleCount: 16)

        XCTAssertEqual(waveform.left.count, 16)
        XCTAssertEqual(waveform.right.count, 16)
        XCTAssertEqual(waveform.left, waveform.right)
        XCTAssertTrue(waveform.left.allSatisfy { abs($0 - 0.5) < 0.01 })
    }

    func testOnWaveformUpdateFiresAfterAsyncProcessing() {
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024, waveformChunkSize: 8)
        let buffer = self.makeStereoBuffer(left: Array(repeating: 0.25, count: 1024), right: Array(repeating: -0.25, count: 1024))
        let updateExpectation = expectation(description: "waveform update")

        analyzer.onWaveformUpdate = { left, right in
            XCTAssertEqual(left.count, 8)
            XCTAssertEqual(right.count, 8)
            XCTAssertTrue(left.allSatisfy { abs($0 - 0.25) < 0.01 })
            XCTAssertTrue(right.allSatisfy { abs($0 + 0.25) < 0.01 })
            updateExpectation.fulfill()
        }

        analyzer.processBufferForTests(buffer)
        wait(for: [updateExpectation], timeout: 2.0)
    }

    private func makeStereoBuffer(left: [Float], right: [Float], sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        guard left.count == right.count,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
              let leftData = buffer.floatChannelData?[0],
              let rightData = buffer.floatChannelData?[1]
        else {
            fatalError("Failed to create stereo audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(left.count)
        memcpy(leftData, left, left.count * MemoryLayout<Float>.size)
        memcpy(rightData, right, right.count * MemoryLayout<Float>.size)
        return buffer
    }

    private func makeBuffer(samples: [Float], sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channelData = buffer.floatChannelData?[0]
        else {
            fatalError("Failed to create audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(channelData, samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }
}

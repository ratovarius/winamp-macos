import AVFoundation
import XCTest

@testable import Winamp

final class WaveformRingBufferTests: XCTestCase {
    func testAppendAndReadResampledConstantSignal() {
        let ring = WaveformRingBuffer()
        let buffer = self.makeStereoBuffer(
            left: Array(repeating: 0.5, count: 512),
            right: Array(repeating: -0.5, count: 512)
        )

        ring.append(pcm: buffer)
        let waveform = ring.readResampled(count: AudioFeatures.waveformSampleCount)

        XCTAssertEqual(waveform.left.count, AudioFeatures.waveformSampleCount)
        XCTAssertEqual(waveform.right.count, AudioFeatures.waveformSampleCount)
        XCTAssertEqual(waveform.left.last ?? 0, 0.5, accuracy: 0.02)
        XCTAssertEqual(waveform.right.last ?? 0, -0.5, accuracy: 0.02)
    }

    func testReadResampledUsesRecentHistory() {
        let ring = WaveformRingBuffer()
        ring.append(pcm: self.makeMonoBuffer(samples: Array(repeating: 0.1, count: 256)))
        ring.append(pcm: self.makeMonoBuffer(samples: Array(repeating: 0.9, count: 256)))

        let waveform = ring.readResampled(count: AudioFeatures.waveformSampleCount)
        XCTAssertGreaterThan(waveform.left.last ?? 0, waveform.left.first ?? 1)
    }

    private func makeMonoBuffer(samples: [Float], sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channelData = buffer.floatChannelData?[0]
        else {
            fatalError("Failed to create mono buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(channelData, samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }

    private func makeStereoBuffer(left: [Float], right: [Float], sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        guard left.count == right.count,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
              let leftData = buffer.floatChannelData?[0],
              let rightData = buffer.floatChannelData?[1]
        else {
            fatalError("Failed to create stereo buffer")
        }
        buffer.frameLength = AVAudioFrameCount(left.count)
        memcpy(leftData, left, left.count * MemoryLayout<Float>.size)
        memcpy(rightData, right, right.count * MemoryLayout<Float>.size)
        return buffer
    }
}

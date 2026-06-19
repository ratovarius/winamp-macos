import AVFoundation
import os

/// Stereo PCM ring buffer (producer: audio analysis, consumer: Metal renderer).
final class WaveformRingBuffer: @unchecked Sendable {
    static let capacity = 4096
    private static let mask = capacity - 1

    private let lock = OSAllocatedUnfairLock()
    private var left = [Float](repeating: 0, count: capacity)
    private var right = [Float](repeating: 0, count: capacity)
    private var writeIndex = 0
    private var totalWritten: UInt64 = 0

    func reset() {
        self.lock.lock()
        self.writeIndex = 0
        self.totalWritten = 0
        self.left = [Float](repeating: 0, count: Self.capacity)
        self.right = [Float](repeating: 0, count: Self.capacity)
        self.lock.unlock()
    }

    func append(pcm buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channels = Int(buffer.format.channelCount)
        self.lock.lock()
        if channels == 1 {
            for frame in 0 ..< frameCount {
                let sample = channelData[0][frame]
                self.left[self.writeIndex] = sample
                self.right[self.writeIndex] = sample
                self.writeIndex = (self.writeIndex + 1) & Self.mask
                self.totalWritten += 1
            }
        } else {
            for frame in 0 ..< frameCount {
                self.left[self.writeIndex] = channelData[0][frame]
                self.right[self.writeIndex] = channelData[1][frame]
                self.writeIndex = (self.writeIndex + 1) & Self.mask
                self.totalWritten += 1
            }
        }
        self.lock.unlock()
    }

    /// Resamples the most recent PCM into `count` display points (oldest → newest).
    func readResampled(count: Int) -> (left: [Float], right: [Float]) {
        guard count > 1 else {
            return (
                Array(repeating: 0, count: max(count, 0)),
                Array(repeating: 0, count: max(count, 0))
            )
        }

        var outLeft = [Float](repeating: 0, count: count)
        var outRight = [Float](repeating: 0, count: count)

        self.lock.lock()
        let available = Int(min(self.totalWritten, UInt64(Self.capacity)))
        guard available > 0 else {
            self.lock.unlock()
            return (outLeft, outRight)
        }

        for displayIndex in 0 ..< count {
            let t = Float(displayIndex) / Float(count - 1)
            let source = t * Float(available - 1)
            let lower = Int(floor(source))
            let upper = min(lower + 1, available - 1)
            let fraction = source - Float(lower)

            let lowerLeft = self.sample(offsetFromEnd: available - 1 - lower, channel: .left)
            let upperLeft = self.sample(offsetFromEnd: available - 1 - upper, channel: .left)
            let lowerRight = self.sample(offsetFromEnd: available - 1 - lower, channel: .right)
            let upperRight = self.sample(offsetFromEnd: available - 1 - upper, channel: .right)

            outLeft[displayIndex] = lowerLeft + (upperLeft - lowerLeft) * fraction
            outRight[displayIndex] = lowerRight + (upperRight - lowerRight) * fraction
        }
        self.lock.unlock()

        return (outLeft, outRight)
    }

    private enum Channel {
        case left
        case right
    }

  private func sample(offsetFromEnd endOffset: Int, channel: Channel) -> Float {
        let index = (self.writeIndex - 1 - endOffset) & Self.mask
        switch channel {
        case .left:
            return self.left[index]
        case .right:
            return self.right[index]
        }
    }
}

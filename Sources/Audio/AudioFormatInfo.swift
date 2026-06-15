import AVFoundation
import Foundation

enum AudioFormatInfo {
    struct Details: Sendable {
        let bitrateKbps: Int
        let sampleRateHz: Double
        let channelCount: Int
    }

    static func read(from url: URL, duration: TimeInterval? = nil) -> Details? {
        readFromAudioFile(url: url, duration: duration)
    }

    static func sampleRateDisplayKHz(_ sampleRateHz: Double) -> String {
        String(Int((sampleRateHz / 1000).rounded()))
    }

    static func channelLabel(_ channelCount: Int) -> String {
        switch channelCount {
        case 1: "mono"
        case 2: "stereo"
        default: "\(channelCount)ch"
        }
    }

    struct ChannelIndicator: Equatable, Sendable {
        let text: String
        let isActive: Bool
    }

    static func channelIndicators(for channelCount: Int) -> [ChannelIndicator] {
        let channels = max(1, channelCount)
        switch channels {
        case 1:
            return [ChannelIndicator(text: self.channelLabel(1), isActive: true)]
        case 2:
            return [
                ChannelIndicator(text: self.channelLabel(1), isActive: false),
                ChannelIndicator(text: self.channelLabel(2), isActive: true),
            ]
        default:
            return [ChannelIndicator(text: self.channelLabel(channels), isActive: true)]
        }
    }

    private static func readFromAudioFile(url: URL, duration: TimeInterval?) -> Details? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        let format = audioFile.fileFormat
        let sampleRate = format.sampleRate
        let channels = max(1, Int(format.channelCount))
        let fileDuration = duration ?? (Double(audioFile.length) / sampleRate)

        let bitsPerSample: Int? = {
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format.formatDescription)?.pointee
            let bits = Int(streamDescription?.mBitsPerChannel ?? 0)
            return bits > 0 ? bits : nil
        }()

        let bitrateKbps = bitrateKbps(
            for: url,
            duration: fileDuration,
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bitsPerSample
        )

        return Details(
            bitrateKbps: bitrateKbps,
            sampleRateHz: sampleRate,
            channelCount: channels
        )
    }

    private static func bitrateKbps(
        for url: URL,
        duration: TimeInterval,
        sampleRate: Double,
        channels: Int,
        bitsPerSample: Int?
    ) -> Int {
        if duration > 0,
           let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > 0
        {
            return max(1, Int((Double(fileSize) * 8.0) / duration / 1000.0))
        }

        let bits = bitsPerSample ?? 16
        return max(1, Int((sampleRate * Double(channels) * Double(bits)) / 1000.0))
    }
}

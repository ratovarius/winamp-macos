import Foundation
import UniformTypeIdentifiers

enum TrackInfoFormatter {
    static func summary(for track: Track) -> String {
        guard let url = track.url else {
            return "No file is associated with this playlist entry."
        }

        var lines: [String] = [
            "Location: \(url.path)",
            "Type: \(self.fileTypeLabel(for: url))",
            "Duration: \(track.formattedDuration)",
        ]

        if track.fileSize > 0 {
            lines.append("Size: \(track.formattedSize)")
        }

        if let details = AudioFormatInfo.read(from: url, duration: track.duration) {
            lines.append("Bitrate: \(details.bitrateKbps) kbps")
            lines.append("Sample rate: \(AudioFormatInfo.sampleRateDisplayKHz(details.sampleRateHz)) kHz")
            lines.append("Channels: \(AudioFormatInfo.channelLabel(details.channelCount))")
        }

        return lines.joined(separator: "\n")
    }

    private static func fileTypeLabel(for url: URL) -> String {
        let ext = url.pathExtension
        if !ext.isEmpty,
           let type = UTType(filenameExtension: ext),
           let description = type.localizedDescription?.nilIfEmpty
        {
            return description
        }
        if !ext.isEmpty {
            return "\(ext.uppercased()) audio"
        }
        return "Audio"
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}

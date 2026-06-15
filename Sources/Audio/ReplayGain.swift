import AVFoundation
import Foundation

/// ReplayGain metadata read from a track, used for volume normalization.
///
/// Values follow the ReplayGain spec: gains are in dB relative to an 89 dB SPL reference,
/// peaks are normalized sample amplitudes (1.0 == full scale). Tags appear as Vorbis comments
/// (FLAC/Ogg) or ID3v2 `TXXX` frames (MP3) and are surfaced by AVFoundation as metadata items.
struct ReplayGain: Sendable, Equatable {
    var trackGainDB: Float?
    var albumGainDB: Float?
    var trackPeak: Float?
    var albumPeak: Float?

    var isEmpty: Bool {
        self.trackGainDB == nil && self.albumGainDB == nil
    }

    /// Linear gain to apply for the requested mode, clamped so the resulting peak never exceeds
    /// full scale (prevents the boost from clipping). Falls back to track gain when album gain is
    /// absent (and vice-versa). Returns 1.0 when no usable gain tag exists.
    func normalizationGain(preferAlbum: Bool, maxBoostDB: Float = 12) -> Float {
        let gainDB: Float?
        let peak: Float?
        if preferAlbum {
            gainDB = self.albumGainDB ?? self.trackGainDB
            peak = self.albumPeak ?? self.trackPeak
        } else {
            gainDB = self.trackGainDB ?? self.albumGainDB
            peak = self.trackPeak ?? self.albumPeak
        }
        guard let gainDB else { return 1.0 }

        let clampedDB = min(gainDB, maxBoostDB)
        var linear = pow(10, clampedDB / 20)
        if let peak, peak > 0 {
            // Don't let normalization push the loudest sample past 0 dBFS.
            linear = min(linear, 1.0 / peak)
        }
        return min(max(linear, 0.05), 4.0)
    }
}

enum ReplayGainReader {
    /// Reads ReplayGain tags from a file's metadata. Synchronous; call off the main thread.
    static func read(from url: URL) -> ReplayGain {
        let asset = AVURLAsset(url: url)
        var items = asset.metadata
        for format in asset.availableMetadataFormats {
            items.append(contentsOf: asset.metadata(forFormat: format))
        }

        var result = ReplayGain()
        for item in items {
            guard let key = self.tagKey(for: item),
                  let value = self.stringValue(for: item)
            else { continue }

            switch key {
            case "replaygain_track_gain": result.trackGainDB = self.parseGainDB(value)
            case "replaygain_album_gain": result.albumGainDB = self.parseGainDB(value)
            case "replaygain_track_peak": result.trackPeak = Float(value.trimmingCharacters(in: .whitespaces))
            case "replaygain_album_peak": result.albumPeak = Float(value.trimmingCharacters(in: .whitespaces))
            default: break
            }
        }
        return result
    }

    /// The lowercased tag name. ID3 `TXXX` frames expose the description as the metadata key;
    /// Vorbis comments expose the comment name directly. Both arrive via `key`/`identifier`.
    private static func tagKey(for item: AVMetadataItem) -> String? {
        let candidates: [String?] = [
            item.key as? String,
            item.identifier?.rawValue,
            item.commonKey?.rawValue,
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            // Identifiers look like "org.id3...TXXX" or "...replaygain_track_gain"; grab the tail.
            let tail = candidate.split(whereSeparator: { $0 == "/" || $0 == "." || $0 == ":" }).last.map(String.init) ?? candidate
            let lowered = tail.lowercased()
            if lowered.hasPrefix("replaygain_") {
                return lowered
            }
        }
        return nil
    }

    private static func stringValue(for item: AVMetadataItem) -> String? {
        if let string = item.stringValue { return string }
        if let number = item.numberValue { return number.stringValue }
        return nil
    }

    /// Parses "-6.48 dB" / "+3.21 dB" / "-6.48" into a dB float.
    private static func parseGainDB(_ raw: String) -> Float? {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: "db", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Float(cleaned)
    }
}

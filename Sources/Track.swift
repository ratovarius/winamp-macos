import AVFoundation
import Foundation

struct Track: Identifiable, Equatable, Sendable {
    let id = UUID()
    let url: URL?
    let title: String
    let artist: String
    let duration: TimeInterval
    let fileSize: Int64
    var lyrics: [LyricLine]?

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    init(title: String, artist: String, duration: TimeInterval = 0, fileSize: Int64 = 0, url: URL? = nil) {
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileSize = fileSize
        self.lyrics = nil
    }

    static func load(from url: URL) async -> Track {
        let metadata = await TrackMetadataLoader.load(from: url)
        return Track(
            title: metadata.title,
            artist: metadata.artist,
            duration: metadata.duration,
            fileSize: metadata.fileSize,
            url: url
        )
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedSize: String {
        let kb = Double(fileSize) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
}

enum TrackMetadataLoader {
    struct Metadata: Sendable {
        let title: String
        let artist: String
        let duration: TimeInterval
        let fileSize: Int64
    }

    static func load(from url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var trackTitle = url.deletingPathExtension().lastPathComponent
        var trackArtist = "Unknown Artist"
        var hasID3Tags = false

        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        for item in commonMetadata {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case "title":
                if let title = try? await item.load(.stringValue) {
                    trackTitle = title
                    hasID3Tags = true
                }
            case "artist":
                if let artist = try? await item.load(.stringValue) {
                    trackArtist = artist
                    hasID3Tags = true
                }
            default:
                break
            }
        }

        if !hasID3Tags {
            let parsed = TrackMetadataParser.parse(from: url)
            trackTitle = parsed.title
            trackArtist = parsed.artist
        }

        let durationTime = try? await asset.load(.duration)
        let trackDuration = durationTime.map { CMTimeGetSeconds($0) } ?? 0
        let fileSize = self.readFileSize(for: url)

        return Metadata(
            title: trackTitle,
            artist: trackArtist,
            duration: trackDuration.isNaN ? 0 : trackDuration,
            fileSize: fileSize
        )
    }

    private static func readFileSize(for url: URL) -> Int64 {
        let isNetwork = FileSystemHelpers.isNetworkVolume(url)

        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = resourceValues.fileSize
        {
            return Int64(size)
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attributes[.size] as? Int64 {
                return size
            }
            if let size = attributes[.size] as? NSNumber {
                return size.int64Value
            }
            if let size = attributes[.size] as? UInt64 {
                return Int64(size)
            }
        }

        if isNetwork,
           let fileHandle = try? FileHandle(forReadingFrom: url)
        {
            defer { try? fileHandle.close() }
            if let endOffset = try? fileHandle.seekToEnd() {
                return Int64(endOffset)
            }
        }

        return 0
    }
}

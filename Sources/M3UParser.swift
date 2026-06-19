import Foundation

enum M3UParser {
    static let supportedExtensions: Set<String> = ["mp3", "flac", "wav"]

    static func isSupportedAudioExtension(_ ext: String) -> Bool {
        self.supportedExtensions.contains(ext.lowercased())
    }

    static func isM3UExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return lower == "m3u" || lower == "m3u8"
    }

    /// Parses M3U content into resolved track URLs (does not verify files exist).
    static func parseTrackURLs(from content: String, playlistDirectory: URL) -> [URL] {
        var urls: [URL] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let trackURL: URL?
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") {
                let path = trimmed.replacingOccurrences(of: "file://", with: "")
                trackURL = URL(fileURLWithPath: path)
            } else {
                trackURL = self.resolveRelativeTrackURL(trimmed, playlistDirectory: playlistDirectory)
            }

            guard let trackURL,
                  isSupportedAudioExtension(trackURL.pathExtension) else { continue }

            urls.append(trackURL)
        }

        return urls
    }

    /// Resolves a playlist-relative entry and rejects paths that escape the playlist directory.
    static func resolveRelativeTrackURL(_ relativePath: String, playlistDirectory: URL) -> URL? {
        let playlistRoot = playlistDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = playlistRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard self.isContainedInDirectory(resolved, directory: playlistRoot) else {
            return nil
        }
        return resolved
    }

    private static func isContainedInDirectory(_ url: URL, directory: URL) -> Bool {
        let directoryPath = directory.path
        let urlPath = url.path
        if urlPath == directoryPath {
            return true
        }
        return urlPath.hasPrefix(directoryPath + "/")
    }
}

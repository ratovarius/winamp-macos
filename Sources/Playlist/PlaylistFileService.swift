import Foundation

struct PlaylistFileService: Sendable {
    let bookmarkStore: SecurityScopedBookmarkStore

    func loadM3UPlaylist(from url: URL) async -> [Track]? {
        self.bookmarkM3UResources(for: url)

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let playlistDirectory = url.deletingLastPathComponent()
        let candidateURLs = M3UParser.parseTrackURLs(from: content, playlistDirectory: playlistDirectory)
        var tracks: [Track] = []

        for trackURL in candidateURLs {
            let resolvedURL = self.resolvedLocalURL(trackURL)
            guard self.bookmarkStore.ensureAccess(for: resolvedURL) else {
                continue
            }
            self.ensureNetworkParentAccess(for: resolvedURL)

            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                await tracks.append(Track.load(from: resolvedURL))
            }
        }

        return tracks
    }

    func bookmarkM3UResources(for url: URL) {
        self.bookmarkStore.saveBookmark(for: url)
        self.bookmarkStore.saveBookmark(for: url.deletingLastPathComponent())
    }

    func collectAudioFiles(in folder: URL) -> [URL] {
        _ = self.bookmarkStore.ensureAccess(for: folder)

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile
            else {
                continue
            }

            if M3UParser.isSupportedAudioExtension(fileURL.pathExtension) {
                fileURLs.append(fileURL)
            }
        }

        return fileURLs
    }

    func resolvedLocalURL(_ trackURL: URL) -> URL {
        if FileSystemHelpers.isNetworkVolume(trackURL) {
            return trackURL
        }
        return trackURL.resolvingSymlinksInPath()
    }

    private func ensureNetworkParentAccess(for url: URL) {
        guard FileSystemHelpers.isNetworkVolume(url) else { return }

        var currentPath = url.deletingLastPathComponent()
        for _ in 0 ..< 3 {
            if FileSystemHelpers.isNetworkVolume(currentPath), currentPath.path != "/Volumes" {
                _ = self.bookmarkStore.ensureAccess(for: currentPath)
                currentPath = currentPath.deletingLastPathComponent()
            } else {
                break
            }
        }
    }
}

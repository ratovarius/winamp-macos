import Foundation
import os

private let bookmarkLogger = Logger(subsystem: "com.winamp.macos", category: "SecurityScopedBookmarks")

private struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
    let usesSecurityScope: Bool
}

final class SecurityScopedBookmarkStore: @unchecked Sendable {
    private struct State {
        var securityScopedRefCounts: [URL: Int] = [:]
        var localBookmarkURLs: Set<URL> = []
        var securityScopedBookmarks: [Data] = []
        var bookmarkPathByIndex: [Int: String] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let bookmarksKey: String
    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        bookmarksKey: String = "WinampSecurityScopedBookmarks"
    ) {
        self.userDefaults = userDefaults
        self.bookmarksKey = bookmarksKey
    }

    deinit {
        releaseAll()
    }

    var bookmarkCount: Int {
        self.state.withLock { $0.securityScopedBookmarks.count }
    }

    var activeScopeCount: Int {
        self.state.withLock { state in
            state.securityScopedRefCounts.values.reduce(0, +) + state.localBookmarkURLs.count
        }
    }

    func hasActiveScope(_ url: URL) -> Bool {
        let normalized = self.normalizedURL(url)
        return self.state.withLock { state in
            (state.securityScopedRefCounts[normalized] ?? 0) > 0 || state.localBookmarkURLs.contains(normalized)
        }
    }

    func restore() {
        guard let bookmarks = userDefaults.array(forKey: bookmarksKey) as? [Data] else {
            return
        }

        self.state.withLock { state in
            state.securityScopedBookmarks = bookmarks
            state.bookmarkPathByIndex.removeAll(keepingCapacity: true)

            var seenPaths = Set<String>()
            var dedupedBookmarks: [Data] = []

            for bookmarkData in bookmarks {
                guard var resolved = Self.resolveBookmark(bookmarkData) else {
                    continue
                }

                var storedData = bookmarkData
                if resolved.isStale {
                    if let refreshed = Self.refreshBookmarkData(
                        for: resolved.url,
                        usesSecurityScope: resolved.usesSecurityScope
                    ) {
                        storedData = refreshed
                        resolved = ResolvedBookmark(
                            url: resolved.url,
                            isStale: false,
                            usesSecurityScope: resolved.usesSecurityScope
                        )
                    } else if !FileManager.default.fileExists(atPath: resolved.url.path) {
                        bookmarkLogger.warning("Dropping stale bookmark for missing path \(resolved.url.path, privacy: .public)")
                        continue
                    }
                }

                let path = self.normalizedURL(resolved.url).path
                if seenPaths.contains(path) {
                    continue
                }
                seenPaths.insert(path)

                let index = dedupedBookmarks.count
                dedupedBookmarks.append(storedData)
                state.bookmarkPathByIndex[index] = path

                if resolved.usesSecurityScope {
                    _ = self.activateResolvedBookmark(resolved, in: &state)
                } else {
                    state.localBookmarkURLs.insert(self.normalizedURL(resolved.url))
                }
            }

            state.securityScopedBookmarks = dedupedBookmarks
            self.userDefaults.set(state.securityScopedBookmarks, forKey: self.bookmarksKey)
        }
    }

    func saveBookmark(for url: URL) {
        let normalized = self.normalizedURL(url)
        let path = normalized.path

        self.state.withLock { state in
            if state.securityScopedBookmarks.contains(where: { existingData in
                guard let resolved = Self.resolveBookmark(existingData) else { return false }
                return self.normalizedURL(resolved.url).path == path
            }) {
                if !self.activateBookmark(forPath: path, in: &state) {
                    state.localBookmarkURLs.insert(normalized)
                }
                return
            }

            if self.persistBookmark(for: normalized, withSecurityScope: true, in: &state) {
                return
            }
            _ = self.persistBookmark(for: normalized, withSecurityScope: false, in: &state)
        }
    }

    @discardableResult
    private func persistBookmark(for url: URL, withSecurityScope: Bool, in state: inout State) -> Bool {
        do {
            let options: URL.BookmarkCreationOptions = withSecurityScope ? [.withSecurityScope] : []
            let bookmarkData = try url.bookmarkData(
                options: options,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let index = state.securityScopedBookmarks.count
            state.securityScopedBookmarks.append(bookmarkData)
            state.bookmarkPathByIndex[index] = url.path
            self.userDefaults.set(state.securityScopedBookmarks, forKey: self.bookmarksKey)

            let resolved = ResolvedBookmark(url: url, isStale: false, usesSecurityScope: withSecurityScope)
            if withSecurityScope {
                if !self.activateResolvedBookmark(resolved, in: &state) {
                    state.localBookmarkURLs.insert(self.normalizedURL(url))
                }
            } else {
                state.localBookmarkURLs.insert(self.normalizedURL(url))
            }

            if FileSystemHelpers.isNetworkVolume(url) {
                self.saveParentBookmarks(startingAt: url.deletingLastPathComponent(), in: &state)
            }
            return true
        } catch {
            bookmarkLogger
                .error("Failed to persist bookmark for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    func ensureAccess(for url: URL) -> Bool {
        let normalized = self.normalizedURL(url)
        if self.hasActiveScope(normalized) || self.hasAncestorScope(for: normalized) {
            return true
        }

        if self.state.withLock({ self.activateBookmark(forPath: normalized.path, in: &$0) }) {
            return true
        }

        if FileSystemHelpers.isNetworkVolume(url) {
            var currentPath = normalized
            while currentPath.path != "/", currentPath.path != "/Volumes" {
                let candidatePath = currentPath.path
                if self.state.withLock({ self.activateBookmark(forPath: candidatePath, in: &$0) }) {
                    return true
                }
                currentPath = currentPath.deletingLastPathComponent()
            }
            bookmarkLogger.debug("Could not obtain security scope for network path \(url.path, privacy: .public)")
            return false
        }

        if FileManager.default.isReadableFile(atPath: normalized.path) {
            return true
        }

        let parentDir = normalized.deletingLastPathComponent()
        if FileManager.default.isReadableFile(atPath: parentDir.path) {
            return true
        }

        bookmarkLogger.debug("Could not obtain security scope for \(url.path, privacy: .public)")
        return false
    }

    func releaseAll() {
        self.state.withLock { state in
            for (url, count) in state.securityScopedRefCounts {
                for _ in 0 ..< count {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            state.securityScopedRefCounts.removeAll()
            state.localBookmarkURLs.removeAll()
        }
    }

    private func normalizedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func hasAncestorScope(for url: URL) -> Bool {
        var current = self.normalizedURL(url).deletingLastPathComponent()
        while current.path != "/" {
            if self.hasActiveScope(current) {
                return true
            }
            current = current.deletingLastPathComponent()
        }
        return false
    }

    @discardableResult
    private func activateBookmark(forPath path: String, in state: inout State) -> Bool {
        let normalizedPath = self.normalizedURL(URL(fileURLWithPath: path)).path
        var bestMatch: (index: Int, bookmarkPath: String)?

        for (index, bookmarkPath) in state.bookmarkPathByIndex {
            guard self.path(normalizedPath, matchesBookmarkPath: bookmarkPath) else { continue }
            if let current = bestMatch {
                if bookmarkPath.count > current.bookmarkPath.count {
                    bestMatch = (index, bookmarkPath)
                }
            } else {
                bestMatch = (index, bookmarkPath)
            }
        }

        guard let match = bestMatch, match.index < state.securityScopedBookmarks.count else {
            return false
        }

        guard var resolved = Self.resolveBookmark(state.securityScopedBookmarks[match.index]) else {
            return false
        }

        if resolved.isStale {
            if let refreshed = Self.refreshBookmarkData(
                for: resolved.url,
                usesSecurityScope: resolved.usesSecurityScope
            ) {
                state.securityScopedBookmarks[match.index] = refreshed
                self.userDefaults.set(state.securityScopedBookmarks, forKey: self.bookmarksKey)
                if let refreshedResolved = Self.resolveBookmark(refreshed) {
                    resolved = refreshedResolved
                }
            }
        }

        if resolved.usesSecurityScope {
            return self.activateResolvedBookmark(resolved, in: &state)
        }

        state.localBookmarkURLs.insert(self.normalizedURL(resolved.url))
        return true
    }

    @discardableResult
    private func activateResolvedBookmark(_ resolved: ResolvedBookmark, in state: inout State) -> Bool {
        let scopedURL = self.normalizedURL(resolved.url)
        if let count = state.securityScopedRefCounts[scopedURL], count > 0 {
            state.securityScopedRefCounts[scopedURL] = count + 1
            return true
        }

        if scopedURL.startAccessingSecurityScopedResource() {
            state.securityScopedRefCounts[scopedURL] = 1
            return true
        }

        return false
    }

    private func path(_ targetPath: String, matchesBookmarkPath bookmarkPath: String) -> Bool {
        targetPath == bookmarkPath || targetPath.hasPrefix(bookmarkPath + "/")
    }

    private static func refreshBookmarkData(for url: URL, usesSecurityScope: Bool) -> Data? {
        let options: URL.BookmarkCreationOptions = usesSecurityScope ? [.withSecurityScope] : []
        return try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveBookmark(_ bookmarkData: Data) -> ResolvedBookmark? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedBookmark(url: url, isStale: isStale, usesSecurityScope: true)
        } catch {
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return ResolvedBookmark(url: url, isStale: isStale, usesSecurityScope: false)
            } catch {
                return nil
            }
        }
    }

    private func saveParentBookmarks(startingAt initialPath: URL, in state: inout State) {
        var currentPath = initialPath
        for _ in 0 ..< 3 {
            guard FileSystemHelpers.isNetworkVolume(currentPath), currentPath.path != "/Volumes" else {
                break
            }

            let path = self.normalizedURL(currentPath).path
            let alreadyHasBookmark = state.securityScopedBookmarks.contains { data in
                guard let resolved = Self.resolveBookmark(data) else { return false }
                return self.normalizedURL(resolved.url).path == path
            }

            if !alreadyHasBookmark {
                _ = self.persistBookmark(for: currentPath, withSecurityScope: true, in: &state)
            } else {
                _ = self.activateBookmark(forPath: path, in: &state)
            }

            currentPath = currentPath.deletingLastPathComponent()
        }
    }
}

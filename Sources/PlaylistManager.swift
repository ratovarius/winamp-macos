import AppKit
import Combine
import Foundation
import os

private let playlistLogger = Logger(subsystem: "com.winamp.macos", category: "Playlist")

struct PlaylistRestoreSummary: Equatable {
    let loadedCount: Int
    let skippedCount: Int
    let skippedPaths: [String]

    var userMessage: String {
        let noun = self.skippedCount == 1 ? "track" : "tracks"
        if self.loadedCount == 0 {
            return "None of the \(self.skippedCount) saved \(noun) could be restored. Re-add your music files to rebuild the playlist."
        }
        let loadedNoun = self.loadedCount == 1 ? "track" : "tracks"
        return "\(self.skippedCount) \(noun) could not be restored (missing file or permission). \(self.loadedCount) \(loadedNoun) loaded."
    }
}

@MainActor
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1
    @Published var shuffleEnabled: Bool = false {
        didSet {
            if self.shuffleEnabled {
                self.generateShuffledIndices()
            } else {
                self.shuffledIndices.removeAll()
                self.shuffleCurrentIndex = 0
            }
            if !self.isRestoringState {
                self.persistState()
            }
        }
    }

    @Published var repeatEnabled: Bool = false {
        didSet {
            if !self.isRestoringState {
                self.persistState()
            }
        }
    }

    @Published private(set) var lastRestoreSummary: PlaylistRestoreSummary?
    @Published private(set) var lastSaveErrorMessage: String?

    private var playRequestGeneration = 0
    private var isRestoringState = false

    // Shuffle management
    private var shuffledIndices: [Int] = []
    private var shuffleCurrentIndex: Int = 0

    private let audioPlayer: AudioPlaybackControlling
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let fileService: PlaylistFileService
    private let stateStore: PlaylistStateStore
    private let developmentSessionStore: DevelopmentSessionStore?

    init(
        audioPlayer: AudioPlaybackControlling = AudioPlayer.shared,
        restoreBookmarks: Bool = true,
        restorePlaylist: Bool = true,
        bookmarkStore: SecurityScopedBookmarkStore? = nil,
        stateStore: PlaylistStateStore? = nil,
        developmentSessionStore: DevelopmentSessionStore? = nil
    ) {
        self.audioPlayer = audioPlayer
        let store = bookmarkStore ?? SecurityScopedBookmarkStore()
        self.bookmarkStore = store
        self.fileService = PlaylistFileService(bookmarkStore: store)
        self.stateStore = stateStore ?? PlaylistStateStore()
        self.developmentSessionStore = developmentSessionStore
        if restoreBookmarks {
            store.restore()
        }
        if restorePlaylist {
            self.restorePlaylistOnLaunch()
        }
    }

    deinit {
        bookmarkStore.releaseAll()
    }

    var currentTrack: Track? {
        guard self.currentIndex >= 0, self.currentIndex < self.tracks.count else { return nil }
        return self.tracks[self.currentIndex]
    }

    /// Startup chime plays only on a fresh launch with no restored playlist.
    var shouldPlayStartupSoundOnLaunch: Bool {
        self.tracks.isEmpty
    }

    func addTrack(_ track: Track) {
        self.tracks.append(track)
        self.persistState()
        if !self.isRestoringState, self.currentIndex == -1 {
            self.scheduleAutoPlayFirstTrackIfNeeded()
        }
    }

    func addTracks(_ newTracks: [Track]) {
        let wasEmpty = self.tracks.isEmpty
        self.tracks.append(contentsOf: newTracks)
        self.persistState()

        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }

        if !self.isRestoringState, wasEmpty, !self.tracks.isEmpty {
            self.scheduleAutoPlayFirstTrackIfNeeded()
        }
    }

    private func scheduleAutoPlayFirstTrackIfNeeded() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self, self.currentIndex == -1, !self.tracks.isEmpty else { return }
            self.playTrack(at: 0)
        }
    }

    func removeTrack(at index: Int) {
        guard index >= 0, index < self.tracks.count else { return }
        self.tracks.remove(at: index)

        // Regenerate shuffle order if shuffle is enabled
        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }

        if self.tracks.isEmpty {
            self.currentIndex = -1
            self.audioPlayer.stop()
        } else if index == self.currentIndex {
            // Removed current track — play what is now at this index (former next track)
            self.currentIndex = min(index, self.tracks.count - 1)
            self.playTrack(at: self.currentIndex)
        } else if index < self.currentIndex {
            self.currentIndex -= 1
        }
        self.persistState()
    }

    func clearPlaylist() {
        self.tracks.removeAll()
        self.currentIndex = -1
        self.shuffledIndices.removeAll()
        self.shuffleCurrentIndex = 0
        self.audioPlayer.stop()
        self.persistState()
    }

    func playTrack(at index: Int) {
        guard index >= 0, index < self.tracks.count else { return }

        self.playRequestGeneration += 1
        let requestId = self.playRequestGeneration
        let previousIndex = self.currentIndex
        self.currentIndex = index
        let track = self.tracks[index]
        self.persistState()

        self.audioPlayer.loadTrack(track) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard requestId == self.playRequestGeneration else { return }
                if success {
                    if self.shuffleEnabled {
                        if let shufflePos = self.shuffledIndices.firstIndex(of: index) {
                            self.shuffleCurrentIndex = shufflePos
                        } else {
                            self.generateShuffledIndices()
                        }
                    }
                    self.audioPlayer.play()
                } else {
                    self.currentIndex = previousIndex
                    self.persistState()
                }
            }
        }
    }

    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < self.tracks.count,
              destinationIndex >= 0, destinationIndex < self.tracks.count
        else {
            return
        }

        let track = self.tracks.remove(at: sourceIndex)
        self.tracks.insert(track, at: destinationIndex)

        if self.currentIndex == sourceIndex {
            self.currentIndex = destinationIndex
        } else if sourceIndex < self.currentIndex, destinationIndex >= self.currentIndex {
            self.currentIndex -= 1
        } else if sourceIndex > self.currentIndex, destinationIndex <= self.currentIndex {
            self.currentIndex += 1
        }

        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }
        self.persistState()
    }

    func next() {
        guard !self.tracks.isEmpty else { return }

        if self.shuffleEnabled {
            self.advanceShuffle(forward: true)
        } else {
            self.advanceSequential(forward: true)
        }
    }

    func previous() {
        guard !self.tracks.isEmpty else { return }

        if self.shuffleEnabled {
            self.advanceShuffle(forward: false)
        } else {
            self.advanceSequential(forward: false)
        }
    }

    private func advanceShuffle(forward: Bool) {
        if self.shuffledIndices.isEmpty {
            self.generateShuffledIndices()
            self.shuffleCurrentIndex = 0
        }

        if forward {
            self.shuffleCurrentIndex += 1

            if self.shuffleCurrentIndex >= self.shuffledIndices.count {
                if self.repeatEnabled {
                    self.generateShuffledIndices()
                    self.shuffleCurrentIndex = 1

                    if self.shuffledIndices.count <= 1 {
                        self.shuffleCurrentIndex = 0
                    }
                } else {
                    self.audioPlayer.stop()
                    return
                }
            }
        } else {
            self.shuffleCurrentIndex -= 1

            if self.shuffleCurrentIndex < 0 {
                if self.repeatEnabled {
                    self.shuffleCurrentIndex = self.shuffledIndices.count - 1
                } else {
                    self.shuffleCurrentIndex = 0
                    return
                }
            }
        }

        let targetIndex = self.shuffledIndices[self.shuffleCurrentIndex]
        self.playTrack(at: targetIndex)
    }

    private func advanceSequential(forward: Bool) {
        if forward {
            let nextIndex = self.currentIndex + 1

            if nextIndex >= self.tracks.count {
                if self.repeatEnabled {
                    self.playTrack(at: 0)
                } else {
                    self.audioPlayer.stop()
                }
            } else {
                self.playTrack(at: nextIndex)
            }
        } else {
            let prevIndex = self.currentIndex > 0 ? self.currentIndex - 1 : (self.repeatEnabled ? self.tracks.count - 1 : 0)
            self.playTrack(at: prevIndex)
        }
    }

    private func generateShuffledIndices() {
        // Generate a shuffled list of indices, ensuring current track is first
        var indices = Array(0 ..< self.tracks.count)

        // Remove current index from the list
        if self.currentIndex >= 0, self.currentIndex < indices.count {
            indices.remove(at: self.currentIndex)
        }

        // Shuffle the remaining indices
        indices.shuffle()

        // Put current index at the beginning
        if self.currentIndex >= 0, self.currentIndex < self.tracks.count {
            self.shuffledIndices = [self.currentIndex] + indices
        } else {
            self.shuffledIndices = indices
        }

        // Don't reset shuffleCurrentIndex here - let the caller manage it
        // This allows us to set it appropriately when regenerating for repeat
    }

    func test_setShuffledIndices(_ indices: [Int], position: Int) {
        self.shuffledIndices = indices
        self.shuffleCurrentIndex = position
    }

    var test_shuffledIndices: [Int] {
        self.shuffledIndices
    }

    var test_shuffleCurrentIndex: Int {
        self.shuffleCurrentIndex
    }

    var test_playRequestGeneration: Int {
        self.playRequestGeneration
    }

    var test_bookmarkStore: SecurityScopedBookmarkStore {
        self.bookmarkStore
    }

    var test_stateStore: PlaylistStateStore {
        self.stateStore
    }

    func persistStateForTests() {
        self.persistState()
    }

    private func persistState() {
        let paths = self.tracks.compactMap { $0.url?.standardizedFileURL.path }
        self.stateStore.saveState(
            PersistedPlaylistState(
                trackPaths: paths,
                currentIndex: self.currentIndex,
                shuffleEnabled: self.shuffleEnabled,
                repeatEnabled: self.repeatEnabled
            )
        )
    }

    private func restorePlaylistOnLaunch() {
        if DevelopmentSessionStore.isEnabled,
           let snapshot = (self.developmentSessionStore ?? DevelopmentSessionStore()).load() {
            (self.audioPlayer as? AudioPlayer)?.applySessionSettings(
                volume: snapshot.volume,
                eq: snapshot.eq
            )
            self.restorePersistedState(from: snapshot.playlist, playback: snapshot.playback)
            return
        }
        self.restorePersistedState()
    }

    private func restorePersistedState(
        from state: PersistedPlaylistState? = nil,
        playback: DevelopmentSessionPlayback? = nil
    ) {
        guard let state = state ?? self.stateStore.loadState(), !state.trackPaths.isEmpty else { return }

        self.isRestoringState = true
        let paths = state.trackPaths
        let savedIndex = state.currentIndex
        let savedShuffle = state.shuffleEnabled
        let savedRepeat = state.repeatEnabled

        Task.detached(priority: .userInitiated) { [bookmarkStore] in
            var restoredTracks: [Track] = []
            var skippedPaths: [String] = []

            for path in paths {
                let url = URL(fileURLWithPath: path)
                guard bookmarkStore.ensureAccess(for: url) else {
                    skippedPaths.append(path)
                    playlistLogger.warning("Skipped restore (no access): \(path, privacy: .public)")
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    skippedPaths.append(path)
                    playlistLogger.warning("Skipped restore (missing file): \(path, privacy: .public)")
                    continue
                }
                await restoredTracks.append(Track.load(from: url))
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.isRestoringState = false }

                if skippedPaths.isEmpty {
                    self.lastRestoreSummary = nil
                } else {
                    self.lastRestoreSummary = PlaylistRestoreSummary(
                        loadedCount: restoredTracks.count,
                        skippedCount: skippedPaths.count,
                        skippedPaths: skippedPaths
                    )
                }

                if restoredTracks.isEmpty {
                    self.currentIndex = -1
                    self.persistState()
                    return
                }

                self.tracks = restoredTracks
                self.repeatEnabled = savedRepeat
                self.currentIndex = min(max(savedIndex, 0), restoredTracks.count - 1)
                self.shuffleEnabled = savedShuffle
                self.persistState()

                let track = restoredTracks[self.currentIndex]
                self.audioPlayer.loadTrack(track) { [weak self] success in
                    guard let self, success else { return }
                    if let playback, playback.positionSeconds > 0 {
                        self.audioPlayer.seek(to: playback.positionSeconds)
                    }
                    if playback?.wasPlaying == true {
                        self.audioPlayer.play()
                    }
                }
            }
        }
    }

    func acknowledgeRestoreSummary() {
        self.lastRestoreSummary = nil
    }

    func acknowledgeSaveError() {
        self.lastSaveErrorMessage = nil
    }

    private func m3uPlaylistContent(relativeTo playlistFile: URL) -> String {
        var content = "#EXTM3U\n"
        for track in self.tracks {
            if let trackUrl = track.url {
                content += self.m3uEntry(for: trackUrl, relativeTo: playlistFile) + "\n"
            }
        }
        return content
    }

    private func m3uEntry(for trackURL: URL, relativeTo playlistFile: URL) -> String {
        let playlistDirectory = playlistFile.deletingLastPathComponent().standardizedFileURL
        let normalizedTrack = trackURL.standardizedFileURL
        let directoryPrefix = playlistDirectory.path + "/"
        let trackPath = normalizedTrack.path
        if trackPath.hasPrefix(directoryPrefix) {
            return String(trackPath.dropFirst(directoryPrefix.count))
        }
        return trackPath
    }

    private func saveM3UPlaylist(to url: URL) {
        do {
            try self.m3uPlaylistContent(relativeTo: url).write(to: url, atomically: true, encoding: .utf8)
            self.lastSaveErrorMessage = nil
        } catch {
            playlistLogger.error("Failed to save M3U playlist: \(error.localizedDescription, privacy: .public)")
            self.lastSaveErrorMessage = "Could not save playlist. Check the folder permissions and try again."
        }
    }

    func testing_saveM3UPlaylist(to url: URL) {
        self.saveM3UPlaylist(to: url)
    }

    func testing_m3uEntry(for trackURL: URL, relativeTo playlistFile: URL) -> String {
        self.m3uEntry(for: trackURL, relativeTo: playlistFile)
    }

    func importDroppedURL(_ url: URL) {
        let ext = url.pathExtension

        if M3UParser.isM3UExtension(ext) {
            self.fileService.bookmarkM3UResources(for: url)
            self.importTracksInBackground { [fileService] in
                await fileService.loadM3UPlaylist(from: url)
            }
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            self.bookmarkStore.saveBookmark(for: url)
            self.addTracksFromFolder(url)
            return
        }

        guard M3UParser.isSupportedAudioExtension(ext) else { return }
        self.bookmarkStore.saveBookmark(for: url)
        self.addTrackFromURL(url)
    }

    private func addTrackFromURL(_ url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let track = await Track.load(from: url)
            await MainActor.run {
                self?.addTrack(track)
            }
        }
    }

    func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.mp3, .wav, .init(filenameExtension: "flac"), .init(filenameExtension: "m3u")].compactMap { $0 }

        panel.begin { [weak self] response in
            guard let self, response == .OK else { return }
            self.importPickedURLs(panel.urls)
        }
    }

    private func importPickedURLs(_ urls: [URL]) {
        for url in urls {
            if M3UParser.isM3UExtension(url.pathExtension) {
                self.fileService.bookmarkM3UResources(for: url)
            } else {
                self.bookmarkStore.saveBookmark(for: url)
            }
        }

        let fileService = self.fileService
        Task.detached(priority: .userInitiated) { [weak self] in
            var newTracks: [Track] = []
            for url in urls {
                if M3UParser.isM3UExtension(url.pathExtension) {
                    if let m3uTracks = await fileService.loadM3UPlaylist(from: url) {
                        newTracks.append(contentsOf: m3uTracks)
                    }
                } else {
                    await newTracks.append(Track.load(from: url))
                }
            }
            await MainActor.run {
                self?.addTracks(newTracks)
            }
        }
    }

    func loadM3UPlaylist(from url: URL) async -> [Track]? {
        await self.fileService.loadM3UPlaylist(from: url)
    }

    func saveM3UPlaylist() {
        guard !self.tracks.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")].compactMap { $0 }
        panel.nameFieldStringValue = "playlist.m3u"
        panel.title = "Save Playlist As"
        panel.message = "Choose a name and location for your playlist"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.showsTagField = false

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            self.saveM3UPlaylist(to: url)
        }
    }

    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.bookmarkStore.saveBookmark(for: url)
                self?.addTracksFromFolder(url)
            }
        }
    }

    private func addTracksFromFolder(_ folder: URL) {
        self.importTracksInBackground { [fileService] in
            let fileURLs = fileService.collectAudioFiles(in: folder)
            var tracks: [Track] = []
            for url in fileURLs {
                await tracks.append(Track.load(from: url))
            }
            return tracks
        }
    }

    private func importTracksInBackground(_ loadTracks: @escaping @Sendable () async -> [Track]?) {
        Task.detached(priority: .userInitiated) {
            guard let tracks = await loadTracks(), !tracks.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.addTracks(tracks)
            }
        }
    }
}

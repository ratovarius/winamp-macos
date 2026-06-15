import Foundation
import os

private let sessionLogger = Logger(subsystem: "com.winamp.macos", category: "DevelopmentSession")

struct DevelopmentSessionPlayback: Codable, Equatable {
    var positionSeconds: Double
    var wasPlaying: Bool
}

struct DevelopmentSessionSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var savedAt: Date
    var volume: Float
    var eq: EQSettings
    var playlist: PersistedPlaylistState
    var playback: DevelopmentSessionPlayback?

    init(
        savedAt: Date = Date(),
        volume: Float,
        eq: EQSettings,
        playlist: PersistedPlaylistState,
        playback: DevelopmentSessionPlayback?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.volume = volume
        self.eq = eq
        self.playlist = playlist
        self.playback = playback
    }
}

/// Persists a human-readable JSON snapshot of the last dev session (DEBUG builds only).
final class DevelopmentSessionStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    static var isEnabled: Bool {
        #if DEBUG
        !Self.isRunningUnderTest
        #else
        ProcessInfo.processInfo.environment["WINAMP_DEV_SESSION"] == "1"
        #endif
    }

    private static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    static func defaultFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["WINAMP_DEV_SESSION_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: false)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Winamp", isDirectory: true)
            .appendingPathComponent("dev-session.json", isDirectory: false)
    }

    func load() -> DevelopmentSessionSnapshot? {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: self.fileURL)
            let snapshot = try self.decoder.decode(DevelopmentSessionSnapshot.self, from: data)
            guard snapshot.schemaVersion == DevelopmentSessionSnapshot.currentSchemaVersion else {
                sessionLogger.warning("Ignoring dev session with unsupported schema \(snapshot.schemaVersion)")
                return nil
            }
            guard snapshot.playlist.trackPaths.isEmpty == false else { return nil }
            return snapshot
        } catch {
            sessionLogger.error("Failed to read dev session: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ snapshot: DevelopmentSessionSnapshot) {
        do {
            let directory = self.fileURL.deletingLastPathComponent()
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try self.encoder.encode(snapshot)
            try data.write(to: self.fileURL, options: .atomic)
            sessionLogger.info("Saved dev session to \(self.fileURL.path, privacy: .public)")
        } catch {
            sessionLogger.error("Failed to save dev session: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum DevelopmentSessionPersistence {
    @MainActor
    static func saveCurrentSession(
        audioPlayer: AudioPlayer = .shared,
        playlistManager: PlaylistManager = .shared,
        store: DevelopmentSessionStore = DevelopmentSessionStore()
    ) {
        guard DevelopmentSessionStore.isEnabled else { return }

        let paths = playlistManager.tracks.compactMap { $0.url?.standardizedFileURL.path }
        guard !paths.isEmpty else {
            return
        }

        let playback: DevelopmentSessionPlayback?
        if playlistManager.currentIndex >= 0 {
            playback = DevelopmentSessionPlayback(
                positionSeconds: audioPlayer.currentTime,
                wasPlaying: audioPlayer.isPlaying
            )
        } else {
            playback = nil
        }

        let snapshot = DevelopmentSessionSnapshot(
            volume: audioPlayer.volume,
            eq: audioPlayer.snapshotEQSettings(),
            playlist: PersistedPlaylistState(
                trackPaths: paths,
                currentIndex: playlistManager.currentIndex,
                shuffleEnabled: playlistManager.shuffleEnabled,
                repeatEnabled: playlistManager.repeatEnabled
            ),
            playback: playback
        )
        store.save(snapshot)
    }
}

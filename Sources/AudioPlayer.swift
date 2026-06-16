import AppKit
import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os
import QuartzCore
import UniformTypeIdentifiers

private let audioLogger = Logger(subsystem: "com.winamp.macos", category: "AudioEngine")

/// Holds the high-frequency playback position on its own observable so the ~10 Hz timer
/// updates only invalidate the small time/seek readouts that observe it — not every view
/// that observes `AudioPlayer`. Keeps the main thread (shared with the Metal visualizer's
/// `draw(in:)`) free of full player-chrome re-renders while a track plays.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var currentTime: TimeInterval = 0
}

@MainActor
class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published var isPlaying = false
    /// Playback position lives on a dedicated observable so its ~10 Hz updates re-render
    /// only the time readouts that observe `playbackClock`, not every view that observes
    /// the player. `currentTime` forwards to it so existing call sites are unchanged.
    let playbackClock = PlaybackClock()
    var currentTime: TimeInterval {
        get { self.playbackClock.currentTime }
        set { self.playbackClock.currentTime = newValue }
    }

    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.75
    @Published var balance: Float = 0
    @Published var currentTrack: Track?
    @Published var currentBitrate: Int = 128
    @Published var currentSampleRate: Double = 44100
    @Published var currentChannels: Int = 2
    @Published var eqBandValues: [Float] = Array(repeating: 0, count: EQSettings.bandCount)
    @Published var eqPreampValue: Float = 0
    @Published var eqEnabled: Bool = true
    @Published var eqAutoEnabled: Bool = false
    /// Bumps whenever the stored preset list changes, so EQ views re-read `eqPresets()`.
    @Published private(set) var eqPresetsRevision = 0
    @Published private(set) var engineIsRunning = false
    /// Volume normalization (ReplayGain). Off by default; opt in via `setVolumeNormalizationEnabled`.
    @Published var volumeNormalizationEnabled = false
    /// Prefer album gain over track gain when both ReplayGain tags are present.
    @Published var volumeNormalizationPreferAlbum = false
    /// ReplayGain tags read from the current track (empty when none / not yet read).
    @Published private(set) var currentReplayGain = ReplayGain()
    private var manualPreampValue: Float = 0
    /// Linear gain applied to the player node for normalization (1.0 = no change).
    private nonisolated(unsafe) var normalizationLinearGain: Float = 1.0

    private nonisolated(unsafe) var audioGraph: AudioGraph?
    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var playerNode: AVAudioPlayerNode?
    private nonisolated(unsafe) var audioFile: AVAudioFile?
    /// The Winamp EQ stage of the processing graph (preamp + parametric EQ).
    private nonisolated(unsafe) var eqEffect: EQAudioEffect?
    private nonisolated(unsafe) var spectrumAnalyzer: FFTSpectrumAnalyzer?
    private nonisolated(unsafe) var spectrumTapInstalled = false
    /// Cached preamp linear gain for spectrum debug logging (tap already includes preamp in the audio path).
    private nonisolated(unsafe) var spectrumDebugPreampLinear: Float = 1.0

    /// Called when scheduled audio reaches the end and auto-advance is enabled.
    var onTrackFinished: (@MainActor @Sendable () -> Void)?
    /// Wired from the app shell for system media keys (`MPRemoteCommandCenter`).
    var onNextTrackRequested: (@MainActor @Sendable () -> Void)?
    var onPreviousTrackRequested: (@MainActor @Sendable () -> Void)?
    private let eqSettingsStore: EQSettingsStore
    private let remoteCommandController = RemoteCommandController()
    private var timer: Timer?
    private nonisolated(unsafe) var shouldAutoAdvance = true
    private nonisolated(unsafe) var isPlayingInternal = false
    private nonisolated(unsafe) var playbackGeneration = 0
    private nonisolated(unsafe) var loadGeneration = 0
    private let audioQueue = DispatchQueue(label: "com.winamp.audio", qos: .userInteractive)

    private nonisolated func runOnMainActor(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    private nonisolated func runOnMainActor(weak player: AudioPlayer?, _ action: @escaping @MainActor @Sendable (AudioPlayer) -> Void) {
        Task { @MainActor in
            guard let player else { return }
            action(player)
        }
    }

    private nonisolated func startEngineIfNeeded(_ engine: AVAudioEngine) -> Bool {
        if engine.isRunning {
            return true
        }
        do {
            try engine.start()
            return true
        } catch {
            audioLogger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private nonisolated func publishEngineRunningState(_ isRunning: Bool, on player: AudioPlayer) {
        player.runOnMainActor(weak: player) { mainPlayer in
            mainPlayer.engineIsRunning = isRunning
        }
    }

    override init() {
        self.installRemoteCommands = true
        self.eqSettingsStore = EQSettingsStore()
        super.init()
        self.setupAudioEngine()
        self.restoreEQSettings()
        self.setupRemoteCommands()
    }

    init(installRemoteCommands: Bool, eqSettingsStore: EQSettingsStore = EQSettingsStore()) {
        self.installRemoteCommands = installRemoteCommands
        self.eqSettingsStore = eqSettingsStore
        super.init()
        self.setupAudioEngine()
        self.restoreEQSettings()
        if installRemoteCommands {
            self.setupRemoteCommands()
        }
    }

    private let installRemoteCommands: Bool

    private func setupAudioEngine() {
        var engineStarted = false
        self.audioQueue.sync {
            // The processing pipeline is declared as an ordered effect chain rather than
            // hand-wired here, so future DSP modules are inserted via `AudioGraph`, not by
            // editing this method. Today the chain is a single stage: the Winamp EQ.
            let eqEffect = EQAudioEffect()
            let graph = AudioGraph()
            graph.build(effects: [eqEffect])

            self.audioGraph = graph
            self.eqEffect = eqEffect
            self.audioEngine = graph.engine
            self.playerNode = graph.source

            engineStarted = self.startEngineIfNeeded(graph.engine)

            self.installSpectrumTapIfNeeded()
        }
        self.engineIsRunning = engineStarted
    }

    private func installSpectrumTapIfNeeded() {
        guard !self.spectrumTapInstalled, let graph = self.audioGraph else { return }

        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount)
        analyzer.onSpectrumFrames = { [weak self] frames, batchDuration in
            guard let self else { return }
            AudioFeatureBus.shared.publishSpectrumFrames(
                frames,
                arrivalTime: CACurrentMediaTime(),
                batchDuration: batchDuration,
                isPlaying: self.isPlayingInternal
            )
        }
        analyzer.onAnalysisUpdate = { [weak self] bands, _, _ in
            guard let self else { return }
            // Build the diagnostic context lazily: the probe throttles to ~1 Hz, so the
            // string and its log10 only run when it actually emits, not on every callback.
            SpectrumAnalyzerDebugProbe.log(
                stage: "publish",
                bands: bands,
                context: String(format: "preamp=%.1fdB tap=mainMixer", 20 * log10(max(self.spectrumDebugPreampLinear, 0.000_01)))
            )
        }
        analyzer.installTap(on: graph.tapPoint)
        self.spectrumAnalyzer = analyzer
        self.spectrumTapInstalled = true
    }

    private func restoreEQSettings() {
        let settings = self.eqSettingsStore.loadSettings()
        self.eqBandValues = settings.bandGainsDB.map { $0 / 12 }
        self.manualPreampValue = settings.preampGainDB / 12
        self.eqPreampValue = self.manualPreampValue
        self.eqEnabled = settings.eqEnabled
        self.eqAutoEnabled = settings.autoEnabled
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
        if self.eqAutoEnabled {
            self.applyAutoPreampCompensation()
        }
    }

    private func persistEQSettings() {
        let settings = self.currentEQSettings()
        self.eqSettingsStore.saveSettings(settings)
    }

    private func currentEQSettings() -> EQSettings {
        EQSettings(
            bandGainsDB: self.eqBandValues.map { $0 * 12 },
            preampGainDB: self.manualPreampValue * 12,
            eqEnabled: self.eqEnabled,
            autoEnabled: self.eqAutoEnabled
        )
    }

    private nonisolated func applyEQSettings(_ settings: EQSettings) {
        guard let eqEffect = self.eqEffect else { return }
        // Bit-perfect passthrough (bypass + unity preamp when flat/disabled) lives in the
        // EQ effect so the policy is testable without an engine; cache the applied gain
        // for the spectrum-debug context string.
        self.spectrumDebugPreampLinear = eqEffect.apply(settings)
    }

    private func setupRemoteCommands() {
        self.remoteCommandController.setHandlers(RemoteCommandController.Handlers(
            play: { [weak self] in self?.playOrResume() },
            pause: { [weak self] in
                guard let self, self.isPlaying else { return }
                self.pause()
            },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.onNextTrackRequested?() },
            previous: { [weak self] in self?.onPreviousTrackRequested?() }
        ))
        self.remoteCommandController.installCommandTargets()
    }

    func loadTrack(_ track: Track, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        let generation = self.loadGeneration + 1
        self.loadGeneration = generation
        self.resetMainActorStateForNewTrack(track)

        self.audioQueue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion?(false) }
                return
            }

            guard generation == self.loadGeneration else {
                self.deliverSupersededLoadCompletion(completion)
                return
            }

            self.isPlayingInternal = false
            self.shouldAutoAdvance = false
            self.audioFile = nil
            self.playbackGeneration += 1

            self.preparePlayerNodeForNewTrack()

            guard let url = track.url else {
                self.runOnMainActor(weak: self) { player in
                    guard generation == player.loadGeneration else {
                        completion?(false)
                        return
                    }
                    player.clearFailedLoadState()
                    completion?(false)
                }
                return
            }

            do {
                let newFile = try AVAudioFile(forReading: url)
                guard generation == self.loadGeneration else {
                    self.deliverSupersededLoadCompletion(completion)
                    return
                }

                let newDuration = Double(newFile.length) / newFile.fileFormat.sampleRate
                let formatDetails = AudioFormatInfo.read(from: url, duration: newDuration)
                let sampleRate = formatDetails?.sampleRateHz ?? newFile.fileFormat.sampleRate
                let channels = formatDetails?.channelCount ?? Int(newFile.fileFormat.channelCount)
                let bitrate = formatDetails?.bitrateKbps ?? 128
                let replayGain = ReplayGainReader.read(from: url)

                self.audioFile = newFile

                self.runOnMainActor(weak: self) { player in
                    guard generation == player.loadGeneration else {
                        completion?(false)
                        return
                    }
                    player.duration = newDuration
                    player.currentSampleRate = sampleRate
                    player.currentChannels = channels
                    player.currentBitrate = bitrate
                    player.currentReplayGain = replayGain
                    player.recomputeNormalizationGain()
                    if player.volumeNormalizationEnabled {
                        player.applyPlayerVolume()
                    }
                    player.updateNowPlayingInfo()
                    if player.eqAutoEnabled {
                        player.applyAutoPreampCompensation()
                    }
                    completion?(true)
                }
            } catch {
                guard generation == self.loadGeneration else {
                    self.deliverSupersededLoadCompletion(completion)
                    return
                }
                self.audioFile = nil
                self.runOnMainActor(weak: self) { player in
                    guard generation == player.loadGeneration else {
                        completion?(false)
                        return
                    }
                    player.clearFailedLoadState()
                    completion?(false)
                }
            }
        }
    }

    private func resetMainActorStateForNewTrack(_ track: Track) {
        self.stopTimer()
        self.isPlaying = false
        self.currentTime = 0
        self.currentTrack = track
    }

    private func clearFailedLoadState() {
        self.currentTrack = nil
        self.duration = 0
        self.currentTime = 0
        self.isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private nonisolated func deliverSupersededLoadCompletion(_ completion: (@MainActor @Sendable (Bool) -> Void)?) {
        guard let completion else { return }
        Task { @MainActor in
            completion(false)
        }
    }

    /// Stops scheduled audio and reuses the attached player node for the next file.
    private nonisolated func preparePlayerNodeForNewTrack() {
        guard let engine = audioEngine else { return }

        if let player = playerNode {
            player.stop()
            player.reset()
            return
        }

        // Defensive: if the source was ever torn down, recreate it and reconnect to the
        // head of the effect chain (the EQ preamp).
        guard let destination = self.eqEffect?.inputNode ?? self.audioGraph?.tapPoint else { return }
        let player = AVAudioPlayerNode()
        self.playerNode = player
        engine.attach(player)
        engine.connect(player, to: destination, format: nil)
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let info = NowPlayingInfo(
            title: track.title,
            artist: track.artist,
            duration: self.duration,
            elapsedTime: self.currentTime,
            isPlaying: self.isPlaying
        )
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info.dictionary
    }

    func play() {
        self.testing_lastTransportAction = .play
        let normalization = self.volumeNormalizationEnabled ? self.normalizationLinearGain : 1.0
        let volume = VolumeModel.appliedGain(position: self.volume, normalizationGain: normalization)
        let balance = self.balance
        self.audioQueue.async { [weak self] in
            guard let self else { return }

            guard let player = self.playerNode,
                  let file = self.audioFile,
                  let engine = self.audioEngine
            else {
                return
            }

            if self.isPlayingInternal {
                return
            }

            guard self.startEngineIfNeeded(engine) else {
                self.publishEngineRunningState(false, on: self)
                return
            }
            self.publishEngineRunningState(true, on: self)

            player.stop()
            player.reset()

            self.shouldAutoAdvance = true
            let generation = self.playbackGeneration

            player.scheduleFile(file, at: nil) { [weak self] in
                self?.runOnMainActor(weak: self) { player in
                    guard generation == player.playbackGeneration else { return }
                    player.handleTrackCompletion()
                }
            }

            player.volume = volume
            player.pan = balance
            player.play()
            self.isPlayingInternal = true

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = true
                player.startTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    func pause() {
        self.testing_lastTransportAction = .pause
        self.audioQueue.async { [weak self] in
            guard let self, self.isPlayingInternal else { return }
            self.playerNode?.pause()
            self.isPlayingInternal = false

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = false
                player.stopTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    func resume() {
        self.testing_lastTransportAction = .resume
        self.audioQueue.async { [weak self] in
            guard let self,
                  let player = self.playerNode,
                  let engine = self.audioEngine,
                  !self.isPlayingInternal else { return }

            guard self.startEngineIfNeeded(engine) else {
                self.publishEngineRunningState(false, on: self)
                return
            }
            self.publishEngineRunningState(true, on: self)

            player.play()
            self.isPlayingInternal = true

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = true
                player.startTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    func stop() {
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            self.shouldAutoAdvance = false
            self.playbackGeneration += 1
            self.playerNode?.stop()
            self.isPlayingInternal = false

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = false
                player.currentTime = 0
                player.stopTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    func togglePlayPause() {
        if self.isPlaying {
            self.pause()
        } else {
            self.playOrResume()
        }
    }

    /// Starts playback from the beginning, or resumes from the current position when paused.
    func playOrResume() {
        if self.isPlaying { return }
        if self.currentTime > 0, self.currentTrack != nil {
            self.resume()
        } else {
            self.play()
        }
    }

    func seek(to time: TimeInterval) {
        self.audioQueue.async { [weak self] in
            guard let self,
                  let file = self.audioFile,
                  let player = self.playerNode else { return }

            let wasPlaying = self.isPlayingInternal
            self.shouldAutoAdvance = false
            self.playbackGeneration += 1
            player.stop()
            player.reset()
            self.isPlayingInternal = false

            let sampleRate = file.fileFormat.sampleRate
            let startFrame = AVAudioFramePosition(time * sampleRate)
            guard startFrame < file.length else {
                self.runOnMainActor(weak: self) { player in
                    player.isPlaying = false
                    player.stopTimer()
                    player.updateNowPlayingInfo()
                }
                return
            }

            let generation = self.playbackGeneration

            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(file.length - startFrame),
                at: nil
            ) { [weak self] in
                self?.runOnMainActor(weak: self) { player in
                    guard generation == player.playbackGeneration else { return }
                    player.handleTrackCompletion()
                }
            }

            if wasPlaying {
                self.shouldAutoAdvance = true
                player.play()
                self.isPlayingInternal = true
            }

            self.runOnMainActor(weak: self) { player in
                player.currentTime = time
                player.isPlaying = wasPlaying
                if wasPlaying {
                    player.startTimer()
                } else {
                    player.stopTimer()
                }
                player.updateNowPlayingInfo()
            }
        }
    }

    func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        self.volume = clamped
        self.applyPlayerVolume()
    }

    /// Applies the current slider position (tapered) and normalization gain to the player node.
    private func applyPlayerVolume() {
        let normalization = self.volumeNormalizationEnabled ? self.normalizationLinearGain : 1.0
        let applied = VolumeModel.appliedGain(position: self.volume, normalizationGain: normalization)
        self.audioQueue.async { [weak self] in
            self?.playerNode?.volume = applied
        }
    }

    func setBalance(_ newBalance: Float) {
        let clamped = max(-1, min(1, newBalance))
        self.balance = clamped
        self.audioQueue.async { [weak self] in
            self?.playerNode?.pan = clamped
        }
    }

    /// Enables/disables ReplayGain volume normalization. Off by default.
    func setVolumeNormalizationEnabled(_ enabled: Bool) {
        self.volumeNormalizationEnabled = enabled
        self.recomputeNormalizationGain()
        self.applyPlayerVolume()
    }

    /// Chooses album vs. track ReplayGain when both are present.
    func setVolumeNormalizationPreferAlbum(_ preferAlbum: Bool) {
        self.volumeNormalizationPreferAlbum = preferAlbum
        self.recomputeNormalizationGain()
        if self.volumeNormalizationEnabled {
            self.applyPlayerVolume()
        }
    }

    /// Recomputes the cached linear normalization gain from the current track's ReplayGain tags.
    private func recomputeNormalizationGain() {
        let gain = self.currentReplayGain.normalizationGain(preferAlbum: self.volumeNormalizationPreferAlbum)
        self.normalizationLinearGain = gain
    }

    func setEQBand(_ band: Int, gain: Float) {
        guard band >= 0, band < self.eqBandValues.count else { return }
        self.eqBandValues[band] = gain / 12
        self.persistEQSettings()
        if self.eqAutoEnabled {
            // AUTO recomputes preamp; bands are never effectively flat here so apply directly.
            self.audioQueue.async { [weak self] in
                self?.eqEffect?.setBandGain(band, decibels: gain)
            }
            self.applyAutoPreampCompensation()
            return
        }
        // Re-apply the whole EQ so bit-perfect passthrough engages when the user returns to flat.
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
    }

    func setEQPreamp(_ normalizedValue: Float) {
        self.manualPreampValue = normalizedValue
        self.eqPreampValue = normalizedValue
        self.persistEQSettings()
        if self.eqAutoEnabled {
            self.applyAutoPreampCompensation()
            return
        }
        // Re-apply the whole EQ so passthrough engages/disengages as the preamp crosses 0 dB.
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
    }

    func setEQEnabled(_ enabled: Bool) {
        self.eqEnabled = enabled
        self.persistEQSettings()
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
        if self.eqAutoEnabled {
            // applyEQSettings wrote the manual preamp; restore AUTO compensation on top.
            self.applyAutoPreampCompensation()
        }
    }

    func setEQAutoEnabled(_ enabled: Bool) {
        self.eqAutoEnabled = enabled
        self.persistEQSettings()
        if enabled {
            self.applyAutoPreampCompensation()
        } else {
            self.eqPreampValue = self.manualPreampValue
            self.applyPreampGainToEngine(decibels: self.manualPreampValue * 12)
        }
    }

    /// Winamp AUTO: reduce preamp when bands are boosted to limit clipping.
    private func applyAutoPreampCompensation() {
        guard self.eqAutoEnabled, self.eqEnabled else { return }
        let bandGainsDB = self.eqBandValues.map { $0 * 12 }
        let compensationDB = EQAudioEffect.autoPreampCompensationDB(forBandGainsDB: bandGainsDB)
        self.eqPreampValue = compensationDB / 12
        self.applyPreampGainToEngine(decibels: compensationDB)
    }

    private func applyPreampGainToEngine(decibels: Float) {
        let linearGain = EQAudioEffect.linearGain(fromDecibels: decibels)
        self.spectrumDebugPreampLinear = linearGain
        self.audioQueue.async { [weak self] in
            self?.eqEffect?.setPreampGain(decibels: decibels)
        }
    }

    func applyEQPreset(_ preset: EQPreset) {
        self.eqBandValues = preset.bandGainsDB.map { $0 / 12 }
        self.manualPreampValue = preset.preampGainDB / 12
        self.eqPreampValue = self.manualPreampValue
        self.persistEQSettings()
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
        if self.eqAutoEnabled {
            self.applyAutoPreampCompensation()
        }
    }

    func resetEQ() {
        self.applyEQPreset(EQPreset.builtIn[0])
        self.eqEnabled = true
        self.eqAutoEnabled = false
        self.persistEQSettings()
        self.audioQueue.async { [weak self] in
            self?.eqEffect?.setBypass(false)
        }
    }

    func eqPresets() -> [EQPreset] {
        self.eqSettingsStore.loadPresets()
    }

    /// Present an open panel for `.eqf`/`.q1` files, import their presets, persist
    /// them alongside the existing list, and apply the first imported preset.
    func importEQFPresets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["eqf", "q1"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.message = "Choose a Winamp equalizer preset file (.eqf or .q1)"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.importEQF(from: url)
            }
        }
    }

    /// Import presets from an `.eqf`/`.q1` file URL (no UI). Returns the imported presets.
    @discardableResult
    func importEQF(from url: URL) -> [EQPreset] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let imported = try? EQFParser.parse(data), !imported.isEmpty
        else {
            audioLogger.error("Failed to import .eqf presets from \(url.lastPathComponent, privacy: .public)")
            return []
        }

        // Merge: keep existing presets, append imported ones (dedupe by name).
        var presets = self.eqSettingsStore.loadPresets()
        let existingNames = Set(presets.map { $0.name.lowercased() })
        let fresh = imported.filter { !existingNames.contains($0.name.lowercased()) }
        presets.append(contentsOf: fresh)
        self.eqSettingsStore.savePresets(presets)
        self.eqPresetsRevision += 1

        if let first = imported.first {
            self.applyEQPreset(first)
        }
        return imported
    }

    private func startTimer() {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickPlaybackUI()
            }
        }
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private func tickPlaybackUI() {
        if self.isPlaying {
            self.refreshCurrentTimeFromEngine()
        } else {
            self.decaySpectrumDisplay()
        }
    }

    private func refreshCurrentTimeFromEngine() {
        self.audioQueue.async { [weak self] in
            guard let self, let time = self.playbackTimeSnapshot() else { return }
            self.runOnMainActor(weak: self) { player in
                guard player.isPlaying else { return }
                player.currentTime = time
            }
        }
    }

    private nonisolated func playbackTimeSnapshot() -> TimeInterval? {
        guard let player = playerNode,
              let lastRenderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: lastRenderTime),
              let file = audioFile
        else {
            return nil
        }
        return Double(playerTime.sampleTime) / file.fileFormat.sampleRate
    }

    private func decaySpectrumDisplay() {
        AudioFeatureBus.shared.setPlaying(false)
    }

    private func handleTrackCompletion() {
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            self.isPlayingInternal = false
            let shouldAdvance = self.shouldAutoAdvance

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = false
                player.stopTimer()
                if shouldAdvance {
                    player.onTrackFinished?()
                }
            }
        }
    }

    func testing_simulateTrackCompletion() {
        self.handleTrackCompletion()
    }

    func testing_afterAudioQueueFlush(completion: @escaping @Sendable () -> Void) {
        self.audioQueue.async {
            completion()
        }
    }

    func testing_shouldAutoAdvance(completion: @escaping @Sendable (Bool) -> Void) {
        self.audioQueue.async { [weak self] in
            completion(self?.shouldAutoAdvance ?? false)
        }
    }

    func testing_markAsPlayingForTests() {
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            self.isPlayingInternal = true
            self.shouldAutoAdvance = true
            self.runOnMainActor(weak: self) { player in
                player.isPlaying = true
            }
        }
    }

    func testing_isPlayingInternal(completion: @escaping @Sendable (Bool) -> Void) {
        self.audioQueue.async { [weak self] in
            completion(self?.isPlayingInternal ?? false)
        }
    }

    enum TestingTransportAction: Equatable {
        case play
        case resume
        case pause
        case stop
    }

    private(set) var testing_lastTransportAction: TestingTransportAction?

    func testing_setPlaybackUIStateForTests(isPlaying: Bool, currentTime: TimeInterval) {
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.audioQueue.async { [weak self] in
            self?.isPlayingInternal = isPlaying
        }
    }

    func testing_playerNodeIdentity(completion: @escaping @Sendable (ObjectIdentifier?) -> Void) {
        self.audioQueue.async { [weak self] in
            completion(self?.playerNode.map { ObjectIdentifier($0) })
        }
    }

    func testing_stopEngineForTests(completion: @escaping @Sendable () -> Void) {
        self.audioQueue.async { [weak self] in
            self?.audioEngine?.stop()
            guard let self else {
                completion()
                return
            }
            self.runOnMainActor(weak: self) { player in
                player.engineIsRunning = false
                completion()
            }
        }
    }

    func testing_playbackTimeSnapshot(completion: @escaping @Sendable (TimeInterval?) -> Void) {
        self.audioQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let snapshot = self.playbackTimeSnapshot()
            completion(snapshot)
        }
    }
}

import AppKit
import SwiftUI

struct ContentView: View {
    private static var positionedWindows = Set<ObjectIdentifier>()

    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var uiScale: WinampUIScale
    @State private var showPlaylist = true
    @State private var showEqualizer = true
    @State private var isShadeMode = false
    @State private var showVisualization = false
    @State private var playlistSize: CGSize = .init(
        width: WinampUIScale.basePanelWidth,
        height: WinampMetrics.defaultPlaylistHeight
    )
    @State private var songDisplayMode: DisplayMode = .scrolling
    @State private var showRemainingTime = false
    @State private var playlistMinimized = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let summary = playlistManager.lastRestoreSummary {
                    PlaylistRestoreNoticeBanner(
                        message: summary.userMessage,
                        isCritical: summary.loadedCount == 0,
                        onDismiss: { self.playlistManager.acknowledgeRestoreSummary() }
                    )
                }

                if let saveError = playlistManager.lastSaveErrorMessage {
                    PlaylistRestoreNoticeBanner(
                        message: saveError,
                        isCritical: true,
                        onDismiss: { self.playlistManager.acknowledgeSaveError() }
                    )
                }

                if self.isShadeMode {
                    ShadeView(
                        isShadeMode: self.$isShadeMode,
                        songDisplayMode: self.$songDisplayMode,
                        showRemainingTime: self.$showRemainingTime
                    )
                } else {
                    MainPlayerView(
                        showPlaylist: self.$showPlaylist,
                        showEqualizer: self.$showEqualizer,
                        isShadeMode: self.$isShadeMode,
                        showVisualization: self.$showVisualization,
                        shuffleEnabled: Binding(
                            get: { self.playlistManager.shuffleEnabled },
                            set: { self.playlistManager.shuffleEnabled = $0 }
                        ),
                        repeatEnabled: Binding(
                            get: { self.playlistManager.repeatEnabled },
                            set: { self.playlistManager.repeatEnabled = $0 }
                        ),
                        songDisplayMode: self.$songDisplayMode,
                        showRemainingTime: self.$showRemainingTime
                    )

                    if self.showEqualizer {
                        EqualizerView()
                    }
                }

                if self.showPlaylist {
                    PlaylistView(playlistSize: self.$playlistSize, isMinimized: self.$playlistMinimized)
                }
            }
            .frame(width: self.uiScale.panelWidth)
            .environment(\.winampUIScale, self.uiScale.scale)

            if self.showVisualization {
                MilkdropVisualizerView()
                    .frame(width: 600, height: 450)
            }
        }
        .fixedSize()
        .background(WinampColors.titleBar)
        .overlay(
            // Raised outer bevel framing the whole stack (classic window edge).
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            WinampColors.borderLight.opacity(0.9),
                            WinampColors.borderLight.opacity(0.3),
                            WinampColors.borderDark.opacity(0.5),
                            WinampColors.borderDark.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .ignoresSafeArea(.all)
        .onAppear {
            self.bindPlaybackCoordination()
            self.setupWindow()
            self.loadStartupSound()
            self.loadPlaylistSize()
            self.loadDisplayMode()
            self.loadTimeDisplayPreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow else { return }
            self.configureWindow(window)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
            if self.showVisualization {
                self.showVisualization = false
            }
        }
        .onChange(of: self.uiScale.level) { _ in
            self.playlistSize = CGSize(width: self.uiScale.panelWidth, height: self.playlistSize.height)
        }
        .onChange(of: self.songDisplayMode) { newMode in
            self.saveDisplayMode(newMode)
        }
        .onChange(of: self.showRemainingTime) { newValue in
            self.saveTimeDisplayPreference(newValue)
        }
        .onChange(of: self.isShadeMode) { newValue in
            if let window = NSApplication.shared.windows.first {
                if newValue {
                    window.level = .floating
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                } else {
                    window.level = .normal
                    window.collectionBehavior = []
                }
            }
        }
    }

    private func bindPlaybackCoordination() {
        self.audioPlayer.onTrackFinished = { [weak playlistManager] in
            playlistManager?.next()
        }
        self.audioPlayer.onNextTrackRequested = { [weak playlistManager] in
            playlistManager?.next()
        }
        self.audioPlayer.onPreviousTrackRequested = { [weak playlistManager] in
            playlistManager?.previous()
        }
    }

    private func setupWindow() {
        // Get all windows and configure them to be borderless
        Task { @MainActor in
            for window in NSApplication.shared.windows {
                self.configureWindow(window)
            }
        }
    }

    private func loadStartupSound() {
        guard self.playlistManager.shouldPlayStartupSoundOnLaunch else { return }

        // Load the startup.mp3 from the app bundle
        guard let startupURL = Bundle.main.url(forResource: "startup", withExtension: "mp3") else {
            return
        }

        // Create a track for the startup sound off the main actor.
        Task { @MainActor in
            let startupTrack = await Track.load(from: startupURL)
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.audioPlayer.loadTrack(startupTrack) { success in
                if success {
                    self.audioPlayer.play()
                }
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        // Keep a titled window with transparent chrome so SwiftUI content can reach the top edge.
        // Stripping .titled and using .borderless leaves a dead titlebar band (the grey bar).
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.styleMask.remove(.borderless)

        window.collectionBehavior = []
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let titleBarColor = NSColor(
            red: 60.0 / 255.0,
            green: 68.0 / 255.0,
            blue: 92.0 / 255.0,
            alpha: 1.0
        )
        window.backgroundColor = titleBarColor
        window.isOpaque = true
        window.hasShadow = true
        // Only the custom title bar should move the window; interactive controls must not.
        window.isMovableByWindowBackground = false

        let windowID = ObjectIdentifier(window)
        guard !Self.positionedWindows.contains(windowID) else { return }
        Self.positionedWindows.insert(windowID)

        if let screen = window.screen {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame

            // Center horizontally, position at top of visible area (below menu bar)
            let x = screenFrame.midX - (windowFrame.width / 2)
            let y = screenFrame.maxY - windowFrame.height - 20 // 20pt below menu bar

            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func loadPlaylistSize() {
        let savedHeight = UserDefaults.standard.double(forKey: "playlistHeight")

        if savedHeight > 0 {
            self.playlistSize = CGSize(width: self.uiScale.panelWidth, height: savedHeight)
        } else {
            self.playlistSize = CGSize(width: self.uiScale.panelWidth, height: self.playlistSize.height)
        }
    }

    private func loadDisplayMode() {
        // Load saved display mode from UserDefaults
        let savedModeString = UserDefaults.standard.string(forKey: "songDisplayMode")

        if let modeString = savedModeString {
            switch modeString {
            case "vestaboard":
                self.songDisplayMode = .vestaboard
            case "scrolling":
                self.songDisplayMode = .scrolling
            case "scrollingUp":
                self.songDisplayMode = .scrollingUp
            case "pixelated":
                self.songDisplayMode = .pixelated
            default:
                self.songDisplayMode = .scrolling
            }
        }
    }

    private func saveDisplayMode(_ mode: DisplayMode) {
        // Save display mode to UserDefaults
        let modeString = switch mode {
        case .vestaboard:
            "vestaboard"
        case .scrolling:
            "scrolling"
        case .scrollingUp:
            "scrollingUp"
        case .pixelated:
            "pixelated"
        }
        UserDefaults.standard.set(modeString, forKey: "songDisplayMode")
    }

    private func loadTimeDisplayPreference() {
        // Load time display preference from UserDefaults
        self.showRemainingTime = UserDefaults.standard.bool(forKey: "showRemainingTime")
    }

    private func saveTimeDisplayPreference(_ value: Bool) {
        // Save time display preference to UserDefaults
        UserDefaults.standard.set(value, forKey: "showRemainingTime")
    }
}

struct PlaylistRestoreNoticeBanner: View {
    let message: String
    let isCritical: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: self.isCritical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(self.isCritical ? .orange : .yellow)
                .padding(.top, 1)

            Text(self.message)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(WinampColors.displayText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(WinampColors.displayText.opacity(0.8))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WinampColors.displayBg)
        .overlay(
            Rectangle()
                .stroke(self.isCritical ? Color.orange.opacity(0.8) : Color.yellow.opacity(0.6), lineWidth: 1)
        )
    }
}

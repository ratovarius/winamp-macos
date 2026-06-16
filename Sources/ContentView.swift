import AppKit
import SwiftUI

struct ContentView: View {
    private static var positionedWindows = Set<ObjectIdentifier>()

    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var uiScale: WinampUIScale
    @StateObject private var panelLayout = WinampPanelLayoutState()
    @State private var showVisualization = false
    @AppStorage(DisplayMode.storageKey) private var songDisplayModeStorage = DisplayMode.scrolling.rawValue
    @AppStorage("showRemainingTime") private var showRemainingTime = false

    private var songDisplayMode: Binding<DisplayMode> {
        Binding(
            get: { DisplayMode(rawValue: self.songDisplayModeStorage) ?? .scrolling },
            set: { self.songDisplayModeStorage = $0.rawValue }
        )
    }

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

                if self.panelLayout.isShadeMode {
                    ShadeView(
                        isShadeMode: self.$panelLayout.isShadeMode,
                        songDisplayMode: self.songDisplayMode,
                        showRemainingTime: self.$showRemainingTime
                    )
                } else {
                    MainPlayerView(
                        showPlaylist: self.$panelLayout.showPlaylist,
                        showEqualizer: self.$panelLayout.showEqualizer,
                        isShadeMode: self.$panelLayout.isShadeMode,
                        showVisualization: self.$showVisualization,
                        shuffleEnabled: Binding(
                            get: { self.playlistManager.shuffleEnabled },
                            set: { self.playlistManager.shuffleEnabled = $0 }
                        ),
                        repeatEnabled: Binding(
                            get: { self.playlistManager.repeatEnabled },
                            set: { self.playlistManager.repeatEnabled = $0 }
                        ),
                        songDisplayMode: self.songDisplayMode,
                        showRemainingTime: self.$showRemainingTime
                    )
                }
            }
            .frame(width: self.uiScale.panelWidth)
            .environment(\.winampUIScale, self.uiScale.scale)

            if self.showVisualization {
                MilkdropVisualizerView()
                    .frame(width: 600, height: 450)
            }
        }
        .winampOuterFrame()
        .ignoresSafeArea(.all)
        .onAppear {
            self.bindPlaybackCoordination()
            self.setupWindow()
            self.loadStartupSound()
            self.panelLayout.setPlaylistWidth(self.uiScale.panelWidth)
            self.syncPanelWindows()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow else { return }
            guard !WinampPanelWindowManager.shared.isPanelWindow(window) else { return }
            self.configureWindow(window)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
            if self.showVisualization {
                self.showVisualization = false
            }
        }
        .onChange(of: self.uiScale.level) { _ in
            self.panelLayout.setPlaylistWidth(self.uiScale.panelWidth)
            self.syncPanelWindows()
        }
        .onChange(of: self.panelLayout.isShadeMode) { newValue in
            self.applyShadeMode(newValue)
            self.syncPanelWindows()
        }
        .onChange(of: self.panelLayout.showEqualizer) { _ in
            self.syncPanelWindows()
        }
        .onChange(of: self.panelLayout.showPlaylist) { _ in
            self.syncPanelWindows()
        }
        .onChange(of: self.panelLayout.playlistSize) { _ in
            WinampPanelWindowManager.shared.syncPanels()
        }
        .onChange(of: self.panelLayout.playlistMinimized) { _ in
            WinampPanelWindowManager.shared.syncPanels()
        }
    }

    private func applyShadeMode(_ enabled: Bool) {
        guard let window = self.mainPlayerWindow() else { return }
        if enabled {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window.level = .normal
            window.collectionBehavior = []
        }
    }

    private func mainPlayerWindow() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            window.isVisible && !WinampPanelWindowManager.shared.isPanelWindow(window)
        } ?? NSApplication.shared.windows.first
    }

    private func syncPanelWindows() {
        guard let window = self.mainPlayerWindow() else { return }

        WinampPanelWindowManager.shared.configure(
            mainWindow: window,
            layoutState: self.panelLayout,
            audioPlayer: self.audioPlayer,
            playlistManager: self.playlistManager,
            uiScale: self.uiScale
        )
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
        Task { @MainActor in
            if let window = self.mainPlayerWindow() {
                self.configureWindow(window)
            }
            self.syncPanelWindows()
        }
    }

    private func loadStartupSound() {
        guard self.playlistManager.shouldPlayStartupSoundOnLaunch else { return }

        guard let startupURL = Bundle.main.url(forResource: "startup", withExtension: "mp3") else {
            return
        }

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
        guard !WinampPanelWindowManager.shared.isPanelWindow(window) else { return }

        WinampWindowConfigurator.apply(to: window)

        let windowID = ObjectIdentifier(window)
        guard !Self.positionedWindows.contains(windowID) else { return }
        Self.positionedWindows.insert(windowID)

        if let screen = window.screen {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame

            let x = screenFrame.midX - (windowFrame.width / 2)
            let y = screenFrame.maxY - windowFrame.height - 20

            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
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

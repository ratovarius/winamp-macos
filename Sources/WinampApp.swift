import AppKit
import SwiftUI

@main
struct WinampApp: App {
    @StateObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var playlistManager = PlaylistManager.shared
    @StateObject private var uiScale = WinampUIScale.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        WinampTypography.registerBundledFonts()
        self.appDelegate.bind(audioPlayer: AudioPlayer.shared, playlistManager: PlaylistManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(self.audioPlayer)
                .environmentObject(self.playlistManager)
                .environmentObject(self.uiScale)
                .preferredColorScheme(.dark)
                .background(Color.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 450, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button("Play/Pause") { self.audioPlayer.togglePlayPause() }
                    .keyboardShortcut("x", modifiers: [])
                Button("Stop") { self.audioPlayer.stop() }
                    .keyboardShortcut("v", modifiers: [])
                Button("Previous Track") { self.playlistManager.previous() }
                    .keyboardShortcut("z", modifiers: [])
                Button("Next Track") { self.playlistManager.next() }
                    .keyboardShortcut("b", modifiers: [])
            }
            CommandMenu("File") {
                Button("Add Files...") { self.playlistManager.showFilePicker() }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("Add Folder...") { self.playlistManager.showFolderPicker() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                ForEach(WinampUIScaleLevel.allCases) { level in
                    Button(level.label) {
                        self.uiScale.setLevel(level)
                    }
                    .disabled(self.uiScale.level == level)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private weak var audioPlayer: AudioPlayer?
    private weak var playlistManager: PlaylistManager?
    private var keyboardEventMonitor: Any?
    private var clickEventMonitor: Any?

    func bind(audioPlayer: AudioPlayer, playlistManager: PlaylistManager) {
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Window chrome is applied in ContentView.setupWindow().
        guard !Self.isRunningUnderTest else { return }
        self.installKeyboardShortcuts()
        self.installSearchDismissOnClickOutside()
    }

    private func installSearchDismissOnClickOutside() {
        self.clickEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window, window.isKeyWindow,
                  let contentView = window.contentView else { return event }

            let locationInContent = contentView.convert(event.locationInWindow, from: nil)
            let hitView = contentView.hitTest(locationInContent)
            MainActor.assumeIsolated {
                WinampPlaylistSearchFocus.handleClick(at: hitView)
            }
            return event
        }
    }

    private func installKeyboardShortcuts() {
        self.keyboardEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let window = NSApp.keyWindow, window.isKeyWindow else { return event }

            if event.keyCode == 53,
               event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                var dismissed = false
                MainActor.assumeIsolated {
                    if WinampPlaylistSearchFocus.isActive {
                        WinampPlaylistSearchFocus.dismissActive()
                        dismissed = true
                    }
                }
                if dismissed { return nil }
            }

            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            else {
                return event
            }

            if let responder = window.firstResponder {
                if let textField = responder as? NSTextField, !textField.stringValue.isEmpty {
                    return event
                }
                if responder is NSTextView {
                    return event
                }
            }

            guard let self else { return event }

            let player = self.audioPlayer
            MainActor.assumeIsolated {
                player?.togglePlayPause()
            }
            return nil
        }
    }

    func applicationDidResignActive(_: Notification) {
        guard !Self.isRunningUnderTest else { return }
        MainActor.assumeIsolated {
            DevelopmentSessionPersistence.saveCurrentSession(
                audioPlayer: self.audioPlayer ?? .shared,
                playlistManager: self.playlistManager ?? .shared
            )
        }
    }

    func applicationWillTerminate(_: Notification) {
        guard !Self.isRunningUnderTest else { return }
        if let monitor = self.keyboardEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.keyboardEventMonitor = nil
        }
        if let monitor = self.clickEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.clickEventMonitor = nil
        }
        MainActor.assumeIsolated {
            DevelopmentSessionPersistence.saveCurrentSession(
                audioPlayer: self.audioPlayer ?? .shared,
                playlistManager: self.playlistManager ?? .shared
            )
        }
    }
}

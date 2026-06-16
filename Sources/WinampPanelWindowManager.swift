import AppKit
import SwiftUI

/// Manages separate floating NSWindows for the equalizer and playlist.
///
/// Drag behavior matches [Webamp's `WindowManager`](https://github.com/captbaritone/webamp/blob/master/packages/webamp/js/components/WindowManager.tsx):
/// a custom mouse-drag loop moves all graph-connected windows together when dragging
/// the main player; dragging EQ/playlist title bars moves only that window.
@MainActor
final class WinampPanelWindowManager {
    static let shared = WinampPanelWindowManager()

    private struct ActiveDrag {
        let movingWindows: [NSWindow]
        let mouseStart: NSPoint
        let startOrigins: [ObjectIdentifier: NSPoint]
    }

    private var windows: [WinampPanelKind: NSWindow] = [:]
    private var hostingControllers: [WinampPanelKind: NSHostingController<AnyView>] = [:]
    private weak var mainWindow: NSWindow?
    private var layoutState: WinampPanelLayoutState?
    private var audioPlayer: AudioPlayer?
    private var playlistManager: PlaylistManager?
    private var uiScale: WinampUIScale?

    private var dockedBelow: [WinampPanelKind: ObjectIdentifier] = [:]
    private var isFloating: [WinampPanelKind: Bool] = [
        .equalizer: false,
        .playlist: false,
    ]
    private var moveObservers: [NSObjectProtocol] = []
    private var dragEventMonitor: Any?
    private var activeDrag: ActiveDrag?

    private init() {}

    func configure(
        mainWindow: NSWindow,
        layoutState: WinampPanelLayoutState,
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager,
        uiScale: WinampUIScale
    ) {
        self.mainWindow = mainWindow
        self.layoutState = layoutState
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
        self.uiScale = uiScale

        self.installResizeObserversIfNeeded()
        self.syncPanels()
    }

    func isPanelWindow(_ window: NSWindow) -> Bool {
        self.windows.values.contains(where: { $0 === window })
    }

    func syncPanels() {
        guard let layoutState else { return }

        let showEQ = layoutState.isEqualizerDocked
        self.setPanelVisible(showEQ, kind: .equalizer) {
            self.makeEqualizerRoot()
        }

        self.setPanelVisible(layoutState.showPlaylist, kind: .playlist) {
            self.makePlaylistRoot()
        }

        self.stackDockedPanels()
    }

    /// Begin a title-bar drag using Webamp's connected-window model.
    func startDrag(leading window: NSWindow, event _: NSEvent) {
        self.endDrag()

        let moving = self.movingWindows(for: window)
        let origins = Dictionary(uniqueKeysWithValues: moving.map { (ObjectIdentifier($0), $0.frame.origin) })
        self.activeDrag = ActiveDrag(
            movingWindows: moving,
            mouseStart: NSEvent.mouseLocation,
            startOrigins: origins
        )

        self.dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let eventType = event.type
            MainActor.assumeIsolated {
                guard let self else { return }
                switch eventType {
                case .leftMouseDragged:
                    self.handleDragMoved()
                case .leftMouseUp:
                    self.endDrag()
                default:
                    break
                }
            }
            return event
        }
    }

    func stackDockedPanels() {
        guard let mainWindow else { return }

        if !self.isFloating[.equalizer, default: false], self.windows[.equalizer] != nil {
            self.positionPanel(.equalizer, below: mainWindow)
        }

        if !self.isFloating[.playlist, default: false], self.windows[.playlist] != nil {
            if let anchor = self.dockAnchorWindow(for: .playlist) {
                self.positionPanel(.playlist, below: anchor)
            }
        }
    }

    // MARK: - Drag

    private func movingWindows(for lead: NSWindow) -> [NSWindow] {
        let visible = self.visibleManagedWindows()
        if lead === self.mainWindow {
            return WinampWindowSnap.traceConnected(from: lead, among: visible)
        }
        return [lead]
    }

    private func handleDragMoved() {
        guard let drag = self.activeDrag else { return }

        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - drag.mouseStart.x
        let deltaY = currentMouse.y - drag.mouseStart.y

        for window in drag.movingWindows {
            guard let start = drag.startOrigins[ObjectIdentifier(window)] else { continue }
            window.setFrameOrigin(NSPoint(x: start.x + deltaX, y: start.y + deltaY))
        }
    }

    private func endDrag() {
        if let monitor = self.dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.dragEventMonitor = nil
        }
        self.activeDrag = nil
        self.refreshDockState()
        self.applySnapIfNeeded()
    }

    // MARK: - Private

    private func installResizeObserversIfNeeded() {
        guard self.moveObservers.isEmpty else { return }

        self.observeWindowNotification(NSWindow.didResizeNotification) { [weak self] window in
            self?.handleWindowResized(window)
        }
        self.observeWindowNotification(NSWindow.didMiniaturizeNotification) { [weak self] window in
            self?.handleMainMiniaturized(window)
        }
        self.observeWindowNotification(NSWindow.didDeminiaturizeNotification) { [weak self] window in
            self?.handleMainDeminiaturized(window)
        }
    }

    private func observeWindowNotification(
        _ name: NSNotification.Name,
        handler: @escaping @MainActor (NSWindow) -> Void
    ) {
        self.moveObservers.append(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    handler(window)
                }
            }
        )
    }

    private func setPanelVisible(
        _ visible: Bool,
        kind: WinampPanelKind,
        @ViewBuilder content: () -> some View
    ) {
        if visible {
            self.showPanel(kind: kind, rootView: AnyView(content()))
        } else {
            self.hidePanel(kind: kind)
        }
    }

    private func showPanel(kind: WinampPanelKind, rootView: AnyView) {
        guard let audioPlayer, let playlistManager, let uiScale else { return }

        let window: NSWindow
        let hosting: NSHostingController<AnyView>

        let decoratedView = AnyView(
            rootView
                .environmentObject(audioPlayer)
                .environmentObject(audioPlayer.playbackClock)
                .environmentObject(playlistManager)
                .environmentObject(uiScale)
                .environment(\.winampUIScale, uiScale.scale)
        )

        if let existing = self.windows[kind], let controller = self.hostingControllers[kind] {
            window = existing
            hosting = controller
            hosting.rootView = decoratedView
        } else {
            hosting = NSHostingController(rootView: decoratedView)
            hosting.view.wantsLayer = true

            window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: true
            )
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            WinampWindowConfigurator.apply(to: window, resizable: false)

            self.windows[kind] = window
            self.hostingControllers[kind] = hosting
            self.isFloating[kind] = false
            self.setDefaultDockParent(for: kind)
        }

        self.sizePanelWindow(kind: kind)
        window.orderFront(nil)
    }

    private func hidePanel(kind: WinampPanelKind) {
        self.windows[kind]?.orderOut(nil)
    }

    private func sizePanelWindow(kind: WinampPanelKind) {
        guard let window = self.windows[kind], let hosting = self.hostingControllers[kind] else { return }

        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let width = self.uiScale?.panelWidth ?? WinampMetrics.panelWidth
        let height = max(fittingSize.height, 50)
        window.setContentSize(NSSize(width: width, height: height))
    }

    private func makeEqualizerRoot() -> some View {
        EqualizerView()
            .winampOuterFrame()
    }

    @ViewBuilder
    private func makePlaylistRoot() -> some View {
        if let layoutState {
            PlaylistView(
                playlistSize: layoutState.playlistSizeBinding,
                isMinimized: layoutState.playlistMinimizedBinding
            )
            .winampOuterFrame()
        }
    }

    private func setDefaultDockParent(for kind: WinampPanelKind) {
        switch kind {
        case .equalizer:
            if let mainWindow {
                self.dockedBelow[kind] = ObjectIdentifier(mainWindow)
            }
        case .playlist:
            if let anchor = self.defaultPlaylistAnchor() {
                self.dockedBelow[kind] = ObjectIdentifier(anchor)
            }
        }
    }

    private func defaultPlaylistAnchor() -> NSWindow? {
        guard let layoutState else { return self.mainWindow }

        let anchor = WinampPanelDocking.playlistAnchor(
            isEqualizerDocked: layoutState.isEqualizerDocked,
            isEqualizerVisible: self.windows[.equalizer]?.isVisible == true,
            isEqualizerFloating: self.isFloating[.equalizer, default: false]
        )

        switch anchor {
        case .equalizer:
            return self.windows[.equalizer]
        case .main:
            return self.mainWindow
        }
    }

    private func dockAnchorWindow(for kind: WinampPanelKind) -> NSWindow? {
        guard let dockID = self.dockedBelow[kind] else { return self.mainWindow }
        if let mainWindow, ObjectIdentifier(mainWindow) == dockID { return mainWindow }
        for (_, window) in self.windows where ObjectIdentifier(window) == dockID {
            return window
        }
        return self.mainWindow
    }

    private func visibleManagedWindows() -> [NSWindow] {
        var result: [NSWindow] = []
        if let mainWindow, mainWindow.isVisible {
            result.append(mainWindow)
        }
        for kind in WinampPanelKind.allCases {
            if let window = self.windows[kind], window.isVisible {
                result.append(window)
            }
        }
        return result
    }

    private func positionPanel(_ kind: WinampPanelKind, below anchor: NSWindow, resize: Bool = true) {
        guard let window = self.windows[kind] else { return }
        if resize {
            self.sizePanelWindow(kind: kind)
        }

        let anchorFrame = anchor.frame
        let panelSize = window.frame.size
        let origin = NSPoint(
            x: anchorFrame.origin.x,
            y: anchorFrame.minY - panelSize.height
        )
        window.setFrameOrigin(origin)
    }

    private func handleWindowResized(_ resized: NSWindow) {
        if resized === self.windows[.playlist] {
            self.sizePanelWindow(kind: .playlist)
            if !self.isFloating[.playlist, default: false] {
                self.stackDockedPanels()
            }
            return
        }

        if resized === self.mainWindow {
            self.stackDockedPanels()
        }
    }

    private func refreshDockState() {
        guard let mainWindow else { return }

        let visible = self.visibleManagedWindows()
        let connected = Set(WinampWindowSnap.traceConnected(from: mainWindow, among: visible))

        for kind in WinampPanelKind.allCases {
            guard let panel = self.windows[kind], panel.isVisible else { continue }

            if connected.contains(panel) {
                self.isFloating[kind] = false
                if let anchor = self.anchorAbove(panel, in: connected) {
                    self.dockedBelow[kind] = ObjectIdentifier(anchor)
                } else {
                    self.dockedBelow[kind] = ObjectIdentifier(mainWindow)
                }
            } else {
                self.isFloating[kind] = true
            }
        }
    }

    private func anchorAbove(_ panel: NSWindow, in connected: Set<NSWindow>) -> NSWindow? {
        let panelBox = WinampWindowSnap.Box(window: panel)
        return connected
            .filter { $0 !== panel }
            .first { other in
                let otherBox = WinampWindowSnap.Box(window: other)
                return otherBox.minY > panelBox.minY
                    && WinampWindowSnap.abuts(panelBox, otherBox)
            }
    }

    private func handleMainMiniaturized(_ window: NSWindow) {
        guard window === self.mainWindow else { return }
        for kind in WinampPanelKind.allCases {
            self.windows[kind]?.orderOut(nil)
        }
    }

    private func handleMainDeminiaturized(_ window: NSWindow) {
        guard window === self.mainWindow else { return }
        self.syncPanels()
    }

    private func applySnapIfNeeded() {
        guard let mainWindow else { return }

        for kind in WinampPanelKind.allCases {
            guard let panel = self.windows[kind], panel.isVisible, self.isFloating[kind, default: false] else {
                continue
            }

            for anchor in self.visibleManagedWindows() where anchor !== panel {
                if let snapped = WinampWindowSnap.snappedOrigin(for: panel, against: anchor) {
                    panel.setFrameOrigin(snapped)
                    self.isFloating[kind] = false
                    self.dockedBelow[kind] = ObjectIdentifier(anchor)
                    break
                }
            }
        }

        if self.windows[.equalizer]?.isVisible == true, !self.isFloating[.equalizer, default: false] {
            self.dockedBelow[.equalizer] = ObjectIdentifier(mainWindow)
        }

        self.stackDockedPanels()
    }
}

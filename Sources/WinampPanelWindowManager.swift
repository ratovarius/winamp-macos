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
        let lead: NSWindow
        let mouseStart: NSPoint
        let startOrigin: NSPoint
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

    func isPlaylistWindow(_ window: NSWindow) -> Bool {
        self.windows[.playlist] === window
    }

    /// Toggle the classic windowshade ("roll up to the title bar") for the given window.
    ///
    /// Matches Winamp's double-click-title behavior. The main window (`isShadeMode`) and playlist
    /// (`playlistMinimized`) each carry a windowshade state in `layoutState`; the EQ has none in
    /// this app, so it is intentionally a no-op rather than miniaturizing to the Dock.
    func toggleWindowshade(for window: NSWindow) {
        guard let layoutState else { return }
        if self.isPlaylistWindow(window) {
            layoutState.playlistMinimized.toggle()
            // The toggle originates from an AppKit mouseDown, outside SwiftUI's transaction, so
            // ContentView's `.onChange(of: playlistMinimized)` is deferred to a later update cycle
            // — the window keeps its old frame until some other event forces a relayout. Resize
            // now so the windowshade tracks the click, matching the SwiftUI chevron path.
            self.resizePlaylistPanel()
        } else if window === self.mainWindow {
            layoutState.isShadeMode.toggle()
        }
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

        self.reanchorDockedPlaylist()
        self.stackDockedPanels()
    }

    /// Resize the playlist panel to match `layoutState` without rebuilding its SwiftUI tree.
    func resizePlaylistPanel() {
        guard self.windows[.playlist]?.isVisible == true else { return }
        self.applyPlaylistContentSize()
        if !self.isFloating[.playlist, default: false] {
            self.repositionDockedPlaylist()
        }
    }

    /// Begin a title-bar drag. The grabbed window is detached from its parent so it moves freely;
    /// its own child windows (the sub-tree docked below it) stay attached and follow atomically via
    /// the WindowServer. Dock relationships are recomputed from geometry on mouse-up.
    func startDrag(leading window: NSWindow, event _: NSEvent) {
        self.endDrag()

        window.parent?.removeChildWindow(window)
        self.activeDrag = ActiveDrag(
            lead: window,
            mouseStart: NSEvent.mouseLocation,
            startOrigin: window.frame.origin
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

        self.syncChildWindowLinks()
    }

    /// Mirror the dock graph onto AppKit parent/child window links. A docked, visible panel becomes
    /// a child window of the window it docks beneath, so the WindowServer moves the whole stack with
    /// its parent (atomic, lag-free) and a dragged panel carries the sub-tree docked below it.
    /// Floating or hidden panels are detached. Only changed links are touched, so it is cheap to
    /// call after any layout pass.
    private func syncChildWindowLinks() {
        for kind in WinampPanelKind.allCases {
            guard let panel = self.windows[kind] else { continue }

            let desiredParent: NSWindow? = panel.isVisible && !self.isFloating[kind, default: false]
                ? self.dockAnchorWindow(for: kind)
                : nil

            guard panel.parent !== desiredParent else { continue }
            panel.parent?.removeChildWindow(panel)
            if let desiredParent, desiredParent !== panel, desiredParent.isVisible {
                desiredParent.addChildWindow(panel, ordered: .above)
            }
        }
    }

    // MARK: - Drag

    private func handleDragMoved() {
        guard let drag = self.activeDrag else { return }

        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - drag.mouseStart.x
        let deltaY = currentMouse.y - drag.mouseStart.y

        // Move only the lead window. Its child windows (the docked sub-tree below it) follow
        // atomically via the WindowServer, so the whole stack tracks the cursor in lockstep — no
        // per-window frame lag, and dragging a mid-stack panel carries everything docked beneath it.
        drag.lead.setFrameOrigin(
            NSPoint(x: drag.startOrigin.x + deltaX, y: drag.startOrigin.y + deltaY)
        )
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

        if let existing = self.windows[kind], self.hostingControllers[kind] != nil {
            window = existing
            // Keep the live view tree — bindings on `layoutState` propagate size changes.
        } else {
            let decoratedView = AnyView(
                rootView
                    .environmentObject(audioPlayer)
                    .environmentObject(audioPlayer.playbackClock)
                    .environmentObject(playlistManager)
                    .environmentObject(uiScale)
                    .environment(\.winampUIScale, uiScale.scale)
            )
            let hosting = NSHostingController(rootView: decoratedView)
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
        guard let window = self.windows[kind] else { return }
        // Detach first: ordering out a window also hides its child windows, which would wrongly hide
        // a panel docked below this one. Re-anchoring + `syncChildWindowLinks` then re-attaches any
        // orphaned sub-tree to a still-visible anchor.
        for child in window.childWindows ?? [] {
            window.removeChildWindow(child)
        }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func sizePanelWindow(kind: WinampPanelKind) {
        switch kind {
        case .playlist:
            self.applyPlaylistContentSize()
        case .equalizer:
            self.applyEqualizerContentSize()
        }
    }

    private func applyPlaylistContentSize() {
        guard let window = self.windows[.playlist], let layoutState else { return }

        let minWidth = self.uiScale?.panelWidth ?? WinampMetrics.panelWidth
        let width = max(layoutState.playlistSize.width, minWidth)
        let height = layoutState.playlistMinimized ? 50 : layoutState.playlistSize.height
        self.setContentSizeWithoutAnimation(window, size: NSSize(width: width, height: height))
    }

    private func applyEqualizerContentSize() {
        guard let window = self.windows[.equalizer], let hosting = self.hostingControllers[.equalizer] else { return }

        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let width = self.uiScale?.panelWidth ?? WinampMetrics.panelWidth
        let height = max(fittingSize.height, 50)
        self.setContentSizeWithoutAnimation(window, size: NSSize(width: width, height: height))
    }

    private func setContentSizeWithoutAnimation(_ window: NSWindow, size: NSSize) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setContentSize(size)
        }
    }

    private func setFrameOriginWithoutAnimation(_ window: NSWindow, origin: NSPoint) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setFrameOrigin(origin)
        }
    }

    private func makeEqualizerRoot() -> some View {
        EqualizerView()
            .winampOuterFrame()
    }

    @ViewBuilder
    private func makePlaylistRoot() -> some View {
        if let layoutState {
            PlaylistPanelRoot(layoutState: layoutState)
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

    /// Re-resolve the docked playlist's dock anchor from current panel visibility.
    ///
    /// `dockedBelow` is a cache seeded once at window creation. A visibility toggle (e.g. hiding
    /// the EQ) otherwise leaves it pointing at the now-hidden EQ, so the playlist stacks below an
    /// invisible window — an EQ-height gap under the main window. Re-running the tested
    /// `WinampPanelDocking.playlistAnchor` decision on each sync keeps the cache honest. A
    /// floating playlist keeps its user-chosen position and is left untouched.
    private func reanchorDockedPlaylist() {
        guard self.windows[.playlist] != nil,
              !self.isFloating[.playlist, default: false],
              let anchor = self.defaultPlaylistAnchor()
        else { return }
        self.dockedBelow[.playlist] = ObjectIdentifier(anchor)
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
        self.setFrameOriginWithoutAnimation(window, origin: origin)
    }

    private func repositionDockedPlaylist() {
        guard let anchor = self.dockAnchorWindow(for: .playlist) else { return }
        self.positionPanel(.playlist, below: anchor, resize: false)
    }

    private func handleWindowResized(_ resized: NSWindow) {
        if resized === self.windows[.playlist] {
            // Size is owned by `layoutState`; only re-anchor when docked.
            if !self.isFloating[.playlist, default: false] {
                self.repositionDockedPlaylist()
            }
            return
        }

        if resized === self.mainWindow {
            self.stackDockedPanels()
        }
    }

    private func refreshDockState() {
        let visible = Set(self.visibleManagedWindows())

        // A panel is docked to whatever window directly abuts it from above — which may itself be a
        // floating panel. This keeps a detached EQ+playlist sub-tree linked (and moving together)
        // instead of only recognizing windows still connected to the main player.
        for kind in WinampPanelKind.allCases {
            guard let panel = self.windows[kind], panel.isVisible else { continue }

            if let anchor = self.anchorAbove(panel, in: visible) {
                self.isFloating[kind] = false
                self.dockedBelow[kind] = ObjectIdentifier(anchor)
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
        // Detach before hiding so AppKit's automatic child-window restore on deminiaturize doesn't
        // race our own `syncPanels`; visibility is re-established explicitly there.
        for kind in WinampPanelKind.allCases {
            guard let panel = self.windows[kind] else { continue }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
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
                    self.setFrameOriginWithoutAnimation(panel, origin: snapped)
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

/// Observing root for the detached playlist window.
///
/// The panel runs in its own `NSHostingController`, which does not inherit the main window's
/// observation of `layoutState`. Holding it as an `@ObservedObject` here makes the panel re-render
/// its body when `playlistMinimized` / `playlistSize` change — so a windowshade toggle reflows the
/// SwiftUI content immediately instead of waiting for an unrelated relayout to force it.
private struct PlaylistPanelRoot: View {
    @ObservedObject var layoutState: WinampPanelLayoutState

    var body: some View {
        PlaylistView(
            playlistSize: self.layoutState.playlistSizeBinding,
            isMinimized: self.layoutState.playlistMinimizedBinding
        )
        .winampOuterFrame(flexibleVertical: true)
    }
}


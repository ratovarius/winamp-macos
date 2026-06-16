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

    private var windows: [WinampPanelID: NSWindow] = [:]
    private var hostingControllers: [WinampPanelID: NSHostingController<AnyView>] = [:]
    private weak var mainWindow: NSWindow?
    private var layoutState: WinampPanelLayoutState?
    private var audioPlayer: AudioPlayer?
    private var playlistManager: PlaylistManager?
    private var uiScale: WinampUIScale?

    private var moveObservers: [NSObjectProtocol] = []
    private var dragEventMonitor: Any?
    private var activeDrag: ActiveDrag?

    /// The set of panels the manager can host, in default top→bottom stack order. Built once;
    /// each descriptor reads live layout state through `self`, so a new panel is added by appending
    /// a descriptor here rather than editing per-kind branches throughout the manager.
    private lazy var registry: [WinampPanelDescriptor] = self.makeRegistry()

    /// The persisted, ordered stack — the single source of truth for dock order and floating state.
    private lazy var stackModel = WinampPanelStackModel(defaultOrder: self.panelIDs)

    private var panelIDs: [WinampPanelID] { self.registry.map(\.id) }

    private func descriptor(for id: WinampPanelID) -> WinampPanelDescriptor? {
        self.registry.first { $0.id == id }
    }

    private func isFloating(_ id: WinampPanelID) -> Bool {
        self.stackModel.floating.contains(id)
    }

    private func visibleIDs() -> Set<WinampPanelID> {
        Set(self.panelIDs.filter { self.windows[$0]?.isVisible == true })
    }

    private func makeRegistry() -> [WinampPanelDescriptor] {
        [
            WinampPanelDescriptor(
                id: .equalizer,
                isVisible: { [weak self] in self?.layoutState?.isEqualizerDocked ?? false },
                makeRoot: { AnyView(EqualizerView().winampOuterFrame()) },
                sizing: .fixedToContent
            ),
            WinampPanelDescriptor(
                id: .playlist,
                isVisible: { [weak self] in self?.layoutState?.showPlaylist ?? false },
                makeRoot: { [weak self] in
                    guard let layoutState = self?.layoutState else { return AnyView(EmptyView()) }
                    return AnyView(PlaylistPanelRoot(layoutState: layoutState))
                },
                sizing: .explicit { [weak self] in
                    guard let layoutState = self?.layoutState else { return .zero }
                    let height = layoutState.playlistMinimized ? 50 : layoutState.playlistSize.height
                    return CGSize(width: layoutState.playlistSize.width, height: height)
                }
            ),
        ]
    }

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
        guard self.layoutState != nil else { return }

        for descriptor in self.registry {
            self.setPanelVisible(descriptor.isVisible(), descriptor: descriptor)
        }

        self.stackDockedPanels()
    }

    /// Resize the playlist panel to match `layoutState` without rebuilding its SwiftUI tree.
    func resizePlaylistPanel() {
        guard self.windows[.playlist]?.isVisible == true,
              let descriptor = self.descriptor(for: .playlist) else { return }
        self.applyContentSize(for: descriptor)
        if !self.isFloating(.playlist) {
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

        // Position the docked panels in model order: each sits flush below its predecessor, the
        // first below the main window. Generic over the registry — no per-panel branches — so a
        // reordered stack (e.g. playlist above EQ) or a new panel just works.
        var anchor = mainWindow
        for id in self.stackModel.dockedStack(visible: self.visibleIDs()) {
            guard let window = self.windows[id] else { continue }
            self.positionPanel(id, below: anchor)
            anchor = window
        }

        self.syncChildWindowLinks()
    }

    /// Mirror the dock graph onto AppKit parent/child window links. A docked, visible panel becomes
    /// a child window of the window it docks beneath, so the WindowServer moves the whole stack with
    /// its parent (atomic, lag-free) and a dragged panel carries the sub-tree docked below it.
    /// Floating or hidden panels are detached. Only changed links are touched, so it is cheap to
    /// call after any layout pass.
    private func syncChildWindowLinks() {
        for id in self.panelIDs {
            guard let panel = self.windows[id] else { continue }

            let desiredParent: NSWindow? = panel.isVisible && !self.isFloating(id)
                ? self.dockAnchorWindow(for: id)
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
        // Reclassify the stack from where the windows landed (geometry → model), then snap every
        // docked panel to its exact flush position. `stackDockedPanels` does the snapping, so no
        // separate snap pass is needed.
        self.refreshDockState()
        self.stackDockedPanels()
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

    private func setPanelVisible(_ visible: Bool, descriptor: WinampPanelDescriptor) {
        if visible {
            self.showPanel(descriptor: descriptor)
        } else {
            self.hidePanel(id: descriptor.id)
        }
    }

    private func showPanel(descriptor: WinampPanelDescriptor) {
        guard let audioPlayer, let playlistManager, let uiScale else { return }

        let id = descriptor.id
        let window: NSWindow

        if let existing = self.windows[id], self.hostingControllers[id] != nil {
            window = existing
            // Keep the live view tree — bindings on `layoutState` propagate size changes.
        } else {
            let decoratedView = AnyView(
                descriptor.makeRoot()
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

            self.windows[id] = window
            self.hostingControllers[id] = hosting
            // A freshly shown panel docks (its place in the order comes from the persisted model).
            self.stackModel.markDocked(id)
        }

        self.applyContentSize(for: descriptor)
        window.orderFront(nil)
    }

    private func hidePanel(id: WinampPanelID) {
        guard let window = self.windows[id] else { return }
        // Detach first: ordering out a window also hides its child windows, which would wrongly hide
        // a panel docked below this one. Re-anchoring + `syncChildWindowLinks` then re-attaches any
        // orphaned sub-tree to a still-visible anchor.
        for child in window.childWindows ?? [] {
            window.removeChildWindow(child)
        }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func applyContentSize(for descriptor: WinampPanelDescriptor) {
        guard let window = self.windows[descriptor.id] else { return }

        let panelWidth = self.uiScale?.panelWidth ?? WinampMetrics.panelWidth
        let size: NSSize

        switch descriptor.sizing {
        case .fixedToContent:
            guard let hosting = self.hostingControllers[descriptor.id] else { return }
            hosting.view.layoutSubtreeIfNeeded()
            let fitting = hosting.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            size = NSSize(width: panelWidth, height: max(fitting.height, 50))
        case let .explicit(provider):
            let desired = provider()
            size = NSSize(width: max(desired.width, panelWidth), height: desired.height)
        }

        self.setContentSizeWithoutAnimation(window, size: size)
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

    /// The window a docked panel sits directly below, resolved from the ordered stack model.
    /// Returns the main window when the panel is the topmost docked entry.
    private func dockAnchorWindow(for id: WinampPanelID) -> NSWindow? {
        guard let anchorID = self.stackModel.anchorAbove(of: id, visible: self.visibleIDs()) else {
            return self.mainWindow
        }
        return self.windows[anchorID] ?? self.mainWindow
    }

    private func positionPanel(_ id: WinampPanelID, below anchor: NSWindow, resize: Bool = true) {
        guard let window = self.windows[id] else { return }
        if resize, let descriptor = self.descriptor(for: id) {
            self.applyContentSize(for: descriptor)
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
            if !self.isFloating(.playlist) {
                self.repositionDockedPlaylist()
            }
            return
        }

        if resized === self.mainWindow {
            self.stackDockedPanels()
        }
    }

    /// Reclassify dock order and floating state from current window geometry (drag-end write-back).
    /// Delegates the ordering to the pure `WinampPanelStackResolver`, then stores the result in the
    /// model — the single source of truth that `stackDockedPanels` and `dockAnchorWindow` read back.
    private func refreshDockState() {
        guard let mainFrame = self.mainWindow?.frame else { return }

        var visibleFrames: [WinampPanelID: CGRect] = [:]
        for id in self.panelIDs {
            if let window = self.windows[id], window.isVisible {
                visibleFrames[id] = window.frame
            }
        }

        let resolved = WinampPanelStackResolver.resolve(
            preferenceOrder: self.stackModel.order,
            visibleFrames: visibleFrames,
            mainFrame: mainFrame
        )
        self.stackModel.update(order: resolved.order, floating: resolved.floating)
    }

    private func handleMainMiniaturized(_ window: NSWindow) {
        guard window === self.mainWindow else { return }
        // Detach before hiding so AppKit's automatic child-window restore on deminiaturize doesn't
        // race our own `syncPanels`; visibility is re-established explicitly there.
        for id in self.panelIDs {
            guard let panel = self.windows[id] else { continue }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func handleMainDeminiaturized(_ window: NSWindow) {
        guard window === self.mainWindow else { return }
        self.syncPanels()
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


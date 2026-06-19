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
        let moving: [NSWindow]
        let startOrigins: [ObjectIdentifier: NSPoint]
        let mouseStart: NSPoint
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

    /// The set of panels the manager can host. Built once; each descriptor reads live layout state
    /// through `self`, so a new panel is added by appending a descriptor here rather than editing
    /// per-kind branches throughout the manager.
    private lazy var registry: [WinampPanelDescriptor] = self.makeRegistry()

    /// Persisted per-panel offset from the main window. In the geometry-primary docking model the
    /// window positions are the source of truth; this is what survives relaunch.
    private let positionStore = WinampPanelPositionStore()

    private var panelIDs: [WinampPanelID] { self.registry.map(\.id) }

    private func descriptor(for id: WinampPanelID) -> WinampPanelDescriptor? {
        self.registry.first { $0.id == id }
    }

    /// Derive the dock parent of every visible panel from current window geometry (the 2D spanning
    /// tree rooted at the main window). Panels absent from the result are floating.
    private func currentDockParents() -> [WinampPanelID: WinampDockNode] {
        guard let mainFrame = self.mainWindow?.frame else { return [:] }
        var frames: [WinampDockNode: CGRect] = [.main: mainFrame]
        for id in self.panelIDs where self.windows[id]?.isVisible == true {
            frames[.panel(id)] = self.windows[id]?.frame ?? .zero
        }
        return WinampDockGraph.parents(frames: frames, order: self.panelIDs)
    }

    private func isFloatingNow(_ id: WinampPanelID) -> Bool {
        self.currentDockParents()[id] == nil
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

    /// Resize the playlist panel to match `layoutState`. Applies the new size **and** origin in a
    /// single `setFrame` so the window never momentarily grows the wrong way and gets repositioned
    /// back (which caused a resize flicker). The top edge stays anchored — to the dock parent's
    /// bottom when docked, or its own current top when floating — matching the bottom-edge handle.
    func resizePlaylistPanel() {
        guard let window = self.windows[.playlist], window.isVisible,
              let descriptor = self.descriptor(for: .playlist) else { return }

        let contentSize = self.targetContentSize(for: descriptor)
        let frameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size

        let topY: CGFloat
        let originX: CGFloat
        if !self.isFloatingNow(.playlist), let anchor = self.dockAnchorWindow(for: .playlist) {
            topY = anchor.frame.minY
            originX = anchor.frame.minX
        } else {
            topY = window.frame.maxY
            originX = window.frame.minX
        }
        let frame = CGRect(x: originX, y: topY - frameSize.height, width: frameSize.width, height: frameSize.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setFrame(frame, display: true)
        }
        self.persistPositions()
    }

    /// Begin a title-bar drag, following Webamp's window-manager model: detach all docked child
    /// links so AppKit doesn't auto-move panels we reposition manually, then drag the **moving set**
    /// as a group. The main window brings its whole connected cluster; a panel moves alone. Dock
    /// links are rebuilt from the final geometry on mouse-up.
    func startDrag(leading window: NSWindow, event _: NSEvent) {
        self.endDrag()

        self.detachAllChildLinks()
        let moving = self.movingSet(for: window)
        let origins = Dictionary(uniqueKeysWithValues: moving.map { (ObjectIdentifier($0), $0.frame.origin) })
        self.activeDrag = ActiveDrag(
            lead: window,
            moving: moving,
            startOrigins: origins,
            mouseStart: NSEvent.mouseLocation
        )

        #if DEBUG
        // TEMP [DRAG] diagnostic.
        DragTrace.log("START lead=\(self.dragLabel(for: window)) moving=\(moving.count)")
        #endif

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

    /// Re-establish the docked arrangement: mirror the geometry-derived dock graph onto AppKit
    /// child-window links. Window positions are the source of truth, so this does not impose an
    /// order — it just reflects where the user put the windows. Called after a panel is shown/hidden
    /// or the main window moves.
    func stackDockedPanels() {
        guard self.mainWindow != nil else { return }
        self.syncChildWindowLinks()
    }

    /// Mirror the geometry-derived dock graph onto AppKit parent/child window links. A docked,
    /// visible panel becomes a child window of the window it abuts toward the main player, so the
    /// WindowServer moves the whole cluster with its parent (atomic, lag-free) and dragging a window
    /// carries its sub-tree. Floating or hidden panels are detached.
    ///
    /// Done in two phases — **detach all changing links, then attach** — so two panels swapping
    /// parent/child roles never transiently form a parent↔child cycle (which makes AppKit recurse
    /// the window graph and crash with SIGSEGV).
    private func syncChildWindowLinks() {
        let parents = self.currentDockParents()
        let desired: [(panel: NSWindow, parent: NSWindow?)] = self.panelIDs.compactMap { id in
            guard let panel = self.windows[id] else { return nil }
            let parent = panel.isVisible ? self.dockParentWindow(for: id, parents: parents) : nil
            return (panel, parent)
        }

        for (panel, parent) in desired where panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
        }
        for (panel, parent) in desired {
            guard let parent, parent !== panel, parent.isVisible, panel.parent !== parent else { continue }
            parent.addChildWindow(panel, ordered: .above)
        }
    }

    private func dockParentWindow(for id: WinampPanelID, parents: [WinampPanelID: WinampDockNode]) -> NSWindow? {
        switch parents[id] {
        case .main: self.mainWindow
        case let .panel(parentID): self.windows[parentID]
        case nil: nil
        }
    }

    /// Detach every managed panel from its parent window, flattening the child-window graph. Done
    /// before a drag so AppKit doesn't auto-move docked panels we are repositioning manually, and
    /// rebuilt from geometry on drop.
    private func detachAllChildLinks() {
        for id in self.panelIDs {
            guard let panel = self.windows[id] else { continue }
            for child in panel.childWindows ?? [] {
                panel.removeChildWindow(child)
            }
            panel.parent?.removeChildWindow(panel)
        }
    }

    // MARK: - Drag

    /// Windows that move together when `lead` is dragged. Per Webamp: the main window carries its
    /// whole geometry-connected cluster; any panel moves by itself.
    private func movingSet(for lead: NSWindow) -> [NSWindow] {
        guard lead === self.mainWindow else { return [lead] }
        return WinampWindowSnap.traceConnected(from: lead, among: self.managedWindowsIncludingMain())
    }

    private func handleDragMoved() {
        guard let drag = self.activeDrag else { return }

        let mouse = NSEvent.mouseLocation
        let proposed = CGSize(
            width: mouse.x - drag.mouseStart.x,
            height: mouse.y - drag.mouseStart.y
        )

        // Webamp group-diff snapping: offset every moving window by the cursor delta, then add one
        // small correction (≤ snapDistance) that snaps the group's edges to the stationary windows.
        // Applying the SAME final delta to all moving windows keeps a dragged cluster rigid and
        // perfectly aligned, and the live correction gives magnetic feedback as you approach an edge.
        let movingBoxes = drag.moving.map { window -> WinampWindowSnap.Box in
            let start = drag.startOrigins[ObjectIdentifier(window)] ?? window.frame.origin
            let origin = NSPoint(x: start.x + proposed.width, y: start.y + proposed.height)
            return WinampWindowSnap.Box(frame: CGRect(origin: origin, size: window.frame.size))
        }
        let movingSet = Set(drag.moving.map { ObjectIdentifier($0) })
        let stationaryBoxes = self.managedWindowsIncludingMain()
            .filter { !movingSet.contains(ObjectIdentifier($0)) }
            .map { WinampWindowSnap.Box(window: $0) }

        let correction = WinampWindowSnap.snapDelta(moving: movingBoxes, stationary: stationaryBoxes)
        let final = CGSize(width: proposed.width + correction.width, height: proposed.height + correction.height)

        for window in drag.moving {
            guard let start = drag.startOrigins[ObjectIdentifier(window)] else { continue }
            window.setFrameOrigin(NSPoint(x: start.x + final.width, y: start.y + final.height))
        }

        #if DEBUG
        // TEMP [DRAG] diagnostic.
        let snapNote = (correction.width != 0 || correction.height != 0)
            ? "SNAP dx=\(Int(correction.width)) dy=\(Int(correction.height))" : "free"
        DragTrace.log("move lead=\(self.dragLabel(for: drag.lead)) n=\(drag.moving.count) stationary=\(stationaryBoxes.count) \(snapNote)")
        #endif
    }

    private func dragLabel(for window: NSWindow) -> String {
        if window === self.mainWindow { return "main" }
        for id in self.panelIDs where self.windows[id] === window { return id.rawValue }
        return "?"
    }

    private func managedWindowsIncludingMain() -> [NSWindow] {
        var result: [NSWindow] = []
        if let mainWindow { result.append(mainWindow) }
        for id in self.panelIDs where self.windows[id]?.isVisible == true {
            if let window = self.windows[id] { result.append(window) }
        }
        return result
    }

    private func endDrag() {
        if let monitor = self.dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.dragEventMonitor = nil
        }
        let wasDragging = self.activeDrag != nil
        self.activeDrag = nil

        // Pull docked windows fully flush to their parents (both axes), then rebuild the dock links
        // and persist. The during-drag snap only aligns the axis you're near, so a window can land
        // docked-but-offset on the perpendicular axis; flushing on drop makes it stick clean — no
        // residual gap that would otherwise ride along when the cluster moves.
        if wasDragging {
            self.flushDockedWindows()
            self.syncChildWindowLinks()
            self.persistPositions()
        }

        #if DEBUG
        // TEMP [DRAG] diagnostic — final arrangement + derived parents.
        if wasDragging {
            let parents = self.currentDockParents()
            let summary = self.panelIDs
                .filter { self.windows[$0]?.isVisible == true }
                .map { id -> String in
                    let frame = self.windows[id]?.frame ?? .zero
                    let parent = parents[id].map { node -> String in
                        switch node {
                        case .main: "main"
                        case let .panel(pid): pid.rawValue
                        }
                    } ?? "FLOATING"
                    return "\(id.rawValue)@(\(Int(frame.minX)),\(Int(frame.minY)))→\(parent)"
                }
                .joined(separator: " ")
            DragTrace.log("END \(summary)")
        }
        #endif
    }

    /// Save every visible panel's offset from the main window so the arrangement restores on relaunch.
    private func persistPositions() {
        guard let mainOrigin = self.mainWindow?.frame.origin else { return }
        for id in self.panelIDs where self.windows[id]?.isVisible == true {
            guard let origin = self.windows[id]?.frame.origin else { continue }
            self.positionStore.store(id, panelOrigin: origin, mainOrigin: mainOrigin)
        }
    }

    /// Align every docked panel flush against its parent on **both** axes (top-down from the main
    /// window). The docking edge is whichever of the four is closest in the current geometry; the
    /// perpendicular axis is aligned to the parent's near edge (left-align when stacked vertically,
    /// top-align when placed side by side) — the classic Winamp flush behavior.
    private func flushDockedWindows() {
        let parents = self.currentDockParents()
        for id in self.dockedBFSOrder(parents: parents) {
            guard let panel = self.windows[id],
                  let parentWindow = self.dockParentWindow(for: id, parents: parents) else { continue }

            let parentFrame = parentWindow.frame
            let size = panel.frame.size
            let panelFrame = panel.frame

            // Gaps to each of the parent's edges (macOS coords: minY = bottom, maxY = top).
            let gapBelow = abs(panelFrame.maxY - parentFrame.minY)
            let gapAbove = abs(panelFrame.minY - parentFrame.maxY)
            let gapRight = abs(panelFrame.minX - parentFrame.maxX)
            let gapLeft = abs(panelFrame.maxX - parentFrame.minX)
            let minGap = min(gapBelow, gapAbove, gapRight, gapLeft)

            let origin: NSPoint = if minGap == gapBelow {
                NSPoint(x: parentFrame.minX, y: parentFrame.minY - size.height)
            } else if minGap == gapAbove {
                NSPoint(x: parentFrame.minX, y: parentFrame.maxY)
            } else if minGap == gapRight {
                NSPoint(x: parentFrame.maxX, y: parentFrame.maxY - size.height)
            } else {
                NSPoint(x: parentFrame.minX - size.width, y: parentFrame.maxY - size.height)
            }
            self.setFrameOriginWithoutAnimation(panel, origin: origin)
        }
    }

    /// Docked panels ordered so a parent always precedes its children (BFS from `.main`).
    private func dockedBFSOrder(parents: [WinampPanelID: WinampDockNode]) -> [WinampPanelID] {
        var ordered: [WinampPanelID] = []
        var frontier: [WinampDockNode] = [.main]
        while !frontier.isEmpty {
            let node = frontier.removeFirst()
            for id in self.panelIDs where parents[id] == node && !ordered.contains(id) {
                ordered.append(id)
                frontier.append(.panel(id))
            }
        }
        return ordered
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
            // The manager owns window sizing (see `applyContentSize`/`resizePlaylistPanel`). Without
            // this, the hosting controller also resizes the window when SwiftUI content changes —
            // anchored origin-fixed, so it grows the wrong way and fights our frame set, flickering.
            hosting.sizingOptions = []

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
            self.applyContentSize(for: descriptor)
            self.placePanelInitially(id)
            window.orderFront(nil)
            return
        }

        self.applyContentSize(for: descriptor)
        window.orderFront(nil)
    }

    /// Position a freshly created panel: at its persisted offset from the main window if known,
    /// otherwise stacked flush below the current bottom of the cluster (the classic default).
    private func placePanelInitially(_ id: WinampPanelID) {
        guard let window = self.windows[id], let mainWindow else { return }
        if let origin = self.positionStore.origin(for: id, mainOrigin: mainWindow.frame.origin) {
            self.setFrameOriginWithoutAnimation(window, origin: origin)
        } else if let bottom = self.lowestVisibleManagedWindow(excluding: id) {
            let origin = NSPoint(x: bottom.frame.minX, y: bottom.frame.minY - window.frame.height)
            self.setFrameOriginWithoutAnimation(window, origin: origin)
        }
    }

    private func lowestVisibleManagedWindow(excluding: WinampPanelID) -> NSWindow? {
        self.managedWindowsIncludingMain()
            .filter { $0 !== self.windows[excluding] }
            .min { $0.frame.minY < $1.frame.minY }
    }

    private func hidePanel(id: WinampPanelID) {
        guard let window = self.windows[id] else { return }
        // Close the vertical gap the panel leaves: detach its child sub-trees and shift any that sat
        // directly below it up by its height, so the cluster stays flush (e.g. hiding the EQ slides
        // the playlist up under the main window). `syncChildWindowLinks` then re-attaches them.
        let gap = window.frame.height
        for child in window.childWindows ?? [] {
            window.removeChildWindow(child)
            if WinampWindowSnap.near(child.frame.maxY, window.frame.minY) {
                child.setFrameOrigin(NSPoint(x: child.frame.minX, y: child.frame.minY + gap))
            }
        }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func applyContentSize(for descriptor: WinampPanelDescriptor) {
        guard let window = self.windows[descriptor.id] else { return }
        self.setContentSizeWithoutAnimation(window, size: self.targetContentSize(for: descriptor))
    }

    /// The content size a panel should have, per its sizing policy.
    private func targetContentSize(for descriptor: WinampPanelDescriptor) -> NSSize {
        let panelWidth = self.uiScale?.panelWidth ?? WinampMetrics.panelWidth
        switch descriptor.sizing {
        case .fixedToContent:
            guard let hosting = self.hostingControllers[descriptor.id] else {
                return NSSize(width: panelWidth, height: 50)
            }
            hosting.view.layoutSubtreeIfNeeded()
            let fitting = hosting.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            return NSSize(width: panelWidth, height: max(fitting.height, 50))
        case let .explicit(provider):
            let desired = provider()
            return NSSize(width: max(desired.width, panelWidth), height: desired.height)
        }
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

    /// The window the docked playlist abuts toward the main player, derived from current geometry.
    private func dockAnchorWindow(for id: WinampPanelID) -> NSWindow? {
        self.dockParentWindow(for: id, parents: self.currentDockParents())
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
            if !self.isFloatingNow(.playlist) {
                self.repositionDockedPlaylist()
                self.persistPositions()
            }
            return
        }

        if resized === self.mainWindow {
            self.stackDockedPanels()
        }
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

#if DEBUG
/// TEMP: lightweight stderr trace for studying drag/magnetism feel. Prints `[DRAG]` lines with a
/// millisecond timestamp so cadence is visible in the streamed terminal output. Remove once the
/// magnetic snapping is tuned. Debug-only — excluded from release builds.
private enum DragTrace {
    private static let start = Date()
    private static let fileURL = URL(fileURLWithPath: "/tmp/winamp_drag.log")
    nonisolated(unsafe) static var handle: FileHandle? = {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        return try? FileHandle(forWritingTo: fileURL)
    }()

    static func log(_ message: String) {
        let ms = Int(Date().timeIntervalSince(self.start) * 1000)
        let line = "[DRAG +\(ms)ms] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        self.handle?.write(Data(line.utf8))
    }
}
#endif

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


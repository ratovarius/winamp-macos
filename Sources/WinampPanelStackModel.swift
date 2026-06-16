import CoreGraphics
import Foundation

/// The single source of truth for **what order** panels stack below the main window.
///
/// Replaces the geometry-derived `dockedBelow` cache and the per-panel anchor special-cases that
/// hard-coded "EQ under main, playlist under EQ". The order is a user preference resolved from
/// window geometry on drag-end (see ``WinampPanelStackResolver``) and persisted across launches;
/// floating state is in-memory and resets to all-docked on launch (window positions are not
/// persisted, so re-floating a panel to a saved spot would be meaningless).
@MainActor
final class WinampPanelStackModel {
    private static let orderKey = "winampPanelStackOrder"

    /// Preference order of all known panels, top→bottom. The visible, non-floating subset forms the
    /// docked stack below the main window.
    private(set) var order: [WinampPanelID]

    /// Panels currently detached from the stack (in-memory; not persisted).
    var floating: Set<WinampPanelID> = []

    private let defaults: UserDefaults

    init(defaultOrder: [WinampPanelID], defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Start from the saved order, keep only still-registered panels, then append any newly
        // registered panels not yet present. So a new panel slots in at its registry position and a
        // removed one drops out, without losing the user's ordering of the rest.
        let saved = (defaults.array(forKey: Self.orderKey) as? [String])?.map(WinampPanelID.init) ?? []
        var resolved = saved.filter(defaultOrder.contains)
        for id in defaultOrder where !resolved.contains(id) {
            resolved.append(id)
        }
        self.order = resolved
    }

    /// Docked panels (visible and not floating) in stack order, top→bottom below the main window.
    func dockedStack(visible: Set<WinampPanelID>) -> [WinampPanelID] {
        self.order.filter { visible.contains($0) && !self.floating.contains($0) }
    }

    /// The panel directly above `id` in the docked stack, or `nil` if `id` is topmost (and therefore
    /// docks below the main window).
    func anchorAbove(of id: WinampPanelID, visible: Set<WinampPanelID>) -> WinampPanelID? {
        let stack = self.dockedStack(visible: visible)
        guard let index = stack.firstIndex(of: id), index > 0 else { return nil }
        return stack[index - 1]
    }

    /// Re-dock a panel (clears its floating flag) without disturbing the order.
    func markDocked(_ id: WinampPanelID) {
        self.floating.remove(id)
    }

    /// Apply a geometry-resolved stack (drag-end write-back) and persist the order.
    func update(order: [WinampPanelID], floating: Set<WinampPanelID>) {
        self.order = order
        self.floating = floating
        self.defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
    }
}

/// Pure reconstruction of the docked stack from window geometry.
///
/// Kept free of AppKit so the ordering logic is unit-testable without live windows — the manager
/// passes plain frames in and gets an order + floating set back. This is the testable core that the
/// stateful manager was previously missing (see the windowing review's W9).
enum WinampPanelStackResolver {
    /// Walk the vertical chain downward from the main window: each step finds the visible panel whose
    /// top edge abuts the current anchor's bottom edge (within snap distance, with horizontal
    /// overlap). Chained panels are docked, in order; visible panels not reachable from the main
    /// window are floating. `preferenceOrder` breaks ties when two panels abut the same anchor and
    /// seeds the persisted order for panels that are not currently docked.
    static func resolve(
        preferenceOrder: [WinampPanelID],
        visibleFrames: [WinampPanelID: CGRect],
        mainFrame: CGRect
    ) -> (order: [WinampPanelID], floating: Set<WinampPanelID>) {
        var chain: [WinampPanelID] = []
        var remaining = Set(visibleFrames.keys)
        var anchorFrame = mainFrame

        while true {
            let candidates = remaining.filter { id in
                guard let frame = visibleFrames[id] else { return false }
                return self.abutsBelow(frame, anchor: anchorFrame)
            }
            guard let next = candidates.min(by: { lhs, rhs in
                self.rank(lhs, in: preferenceOrder) < self.rank(rhs, in: preferenceOrder)
            }) else { break }
            chain.append(next)
            remaining.remove(next)
            anchorFrame = visibleFrames[next] ?? anchorFrame
        }

        // Rebuild the full preference order: the docked chain first, then everything else in its
        // prior relative order, so hidden / floating panels keep their place.
        var newOrder = chain
        for id in preferenceOrder where !chain.contains(id) {
            newOrder.append(id)
        }
        for id in remaining where !newOrder.contains(id) {
            newOrder.append(id)
        }
        return (newOrder, remaining)
    }

    private static func rank(_ id: WinampPanelID, in order: [WinampPanelID]) -> Int {
        order.firstIndex(of: id) ?? Int.max
    }

    /// True when `panel`'s top edge sits just under `anchor`'s bottom edge with horizontal overlap —
    /// i.e. `panel` is docked directly below `anchor`.
    private static func abutsBelow(_ panel: CGRect, anchor: CGRect) -> Bool {
        let panelBox = WinampWindowSnap.Box(frame: panel)
        let anchorBox = WinampWindowSnap.Box(frame: anchor)
        return WinampWindowSnap.overlapX(panelBox, anchorBox)
            && WinampWindowSnap.near(panelBox.maxY, anchorBox.minY)
    }
}

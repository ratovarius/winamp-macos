import CoreGraphics

/// A node in the docking graph: either the root main player or a managed panel.
enum WinampDockNode: Hashable {
    case main
    case panel(WinampPanelID)
}

/// Pure, geometry-primary docking resolution.
///
/// In the geometry-primary model the window *positions* are the source of truth and the dock
/// structure is **derived** from them — there is no stored order or tree. This reconstructs the
/// parent/child spanning tree (rooted at the main window) from the current frames, so the manager
/// can mirror it onto AppKit `addChildWindow` links and so panels not connected to the main cluster
/// are reported as floating.
///
/// Free of AppKit so it is unit-testable without live windows (the manager passes frames in). The
/// adjacency test is the existing 2D Webamp port `WinampWindowSnap.abuts`, so left/right docking
/// works exactly like top/bottom.
enum WinampDockGraph {
    /// BFS spanning tree from `.main`: each window adopts as parent the first abutting window
    /// discovered closer to the root. `order` makes the traversal deterministic when a panel abuts
    /// more than one window (earlier-ordered neighbors win), matching the registry's preference.
    ///
    /// - Returns: each docked panel mapped to its parent node. Panels absent from the result are
    ///   not connected to the main cluster (i.e. floating).
    static func parents(
        frames: [WinampDockNode: CGRect],
        order: [WinampPanelID]
    ) -> [WinampPanelID: WinampDockNode] {
        let traversal: [WinampDockNode] = [.main] + order.map(WinampDockNode.panel)

        var parents: [WinampPanelID: WinampDockNode] = [:]
        var visited: Set<WinampDockNode> = [.main]
        var queue: [WinampDockNode] = [.main]

        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard let nodeFrame = frames[node] else { continue }
            let nodeBox = WinampWindowSnap.Box(frame: nodeFrame)

            for candidate in traversal where !visited.contains(candidate) {
                guard case let .panel(id) = candidate, let frame = frames[candidate] else { continue }
                if WinampWindowSnap.abuts(nodeBox, WinampWindowSnap.Box(frame: frame)) {
                    parents[id] = node
                    visited.insert(candidate)
                    queue.append(candidate)
                }
            }
        }

        return parents
    }

    /// Panels in `order` that are not connected to the main cluster, given the derived parents.
    static func floating(
        order: [WinampPanelID],
        parents: [WinampPanelID: WinampDockNode]
    ) -> Set<WinampPanelID> {
        Set(order.filter { parents[$0] == nil })
    }
}

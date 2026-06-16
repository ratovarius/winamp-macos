import SwiftUI

/// Stable identifier for a managed panel.
///
/// A struct wrapping a string rather than a closed enum, so new panels can define their own IDs
/// (e.g. in a future visualizer module) without editing a central type. This is the open-set half
/// of the modular panel system — the manager iterates the descriptor registry, never a fixed enum.
struct WinampPanelID: Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static let equalizer = WinampPanelID("equalizer")
    static let playlist = WinampPanelID("playlist")
}

/// How a panel window is sized (Strategy pattern). Replaces the per-kind sizing `switch` that used
/// to live in the window manager.
enum PanelSizingPolicy {
    /// Width follows the scaled panel width; height follows the SwiftUI content's intrinsic fitting
    /// size. Used by fixed-skin panels such as the equalizer.
    case fixedToContent

    /// Size is supplied by the panel's own (user-resizable) state. The provider returns the desired
    /// content size; the manager clamps width to at least the scaled panel width. Used by the
    /// playlist.
    case explicit(@MainActor () -> CGSize)
}

/// Everything the window manager needs to host one panel, expressed as data instead of per-kind
/// control flow. Adding a panel becomes "append a descriptor to the registry": the manager stays
/// panel-agnostic for visibility, view-building, and sizing.
///
/// Docking order/anchoring is still resolved separately by the manager (see the M2 ordered stack
/// model); a descriptor does not yet declare where in the stack it sits.
struct WinampPanelDescriptor {
    let id: WinampPanelID

    /// Whether the panel should currently be shown, read live from layout state.
    let isVisible: @MainActor () -> Bool

    /// Builds the panel's SwiftUI root. Classic Winamp chrome is applied inside this closure, so the
    /// descriptor carries no AppKit/window styling and the rendered look is unchanged.
    let makeRoot: @MainActor () -> AnyView

    let sizing: PanelSizingPolicy
}

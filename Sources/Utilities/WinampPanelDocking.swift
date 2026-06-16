/// Docking decisions for detachable Winamp panels (testable without AppKit windows).
enum WinampPanelDocking {
    enum PlaylistAnchor {
        case main
        case equalizer
    }

    static func playlistAnchor(
        isEqualizerDocked: Bool,
        isEqualizerVisible: Bool,
        isEqualizerFloating: Bool
    ) -> PlaylistAnchor {
        if isEqualizerDocked, isEqualizerVisible, !isEqualizerFloating {
            return .equalizer
        }
        return .main
    }
}

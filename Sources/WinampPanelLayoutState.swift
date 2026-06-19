import SwiftUI

/// Layout state shared between the main window and detachable EQ / playlist panels.
@MainActor
final class WinampPanelLayoutState: ObservableObject {
    private static let playlistHeightKey = "playlistHeight"
    private static let playlistWidthKey = "playlistWidth"

    @Published var showEqualizer = true
    @Published var showPlaylist = true
    @Published var isShadeMode = false
    @Published var playlistMinimized = false
    @Published var playlistSize: CGSize {
        didSet {
            if oldValue.height != self.playlistSize.height {
                UserDefaults.standard.set(self.playlistSize.height, forKey: Self.playlistHeightKey)
            }
            if oldValue.width != self.playlistSize.width {
                UserDefaults.standard.set(self.playlistSize.width, forKey: Self.playlistWidthKey)
            }
        }
    }

    init() {
        let savedHeight = UserDefaults.standard.double(forKey: Self.playlistHeightKey)
        let height = savedHeight > 0 ? savedHeight : WinampMetrics.defaultPlaylistHeight
        let savedWidth = UserDefaults.standard.double(forKey: Self.playlistWidthKey)
        let width = savedWidth > 0 ? savedWidth : WinampUIScale.basePanelWidth
        self.playlistSize = CGSize(width: width, height: height)
    }

    /// Ensure the playlist is at least as wide as its docking anchor (the main window). The user
    /// may drag it wider; a UI-scale change only grows it up to the new minimum and never shrinks a
    /// user-widened playlist.
    func ensureMinimumPlaylistWidth(_ minWidth: CGFloat) {
        guard self.playlistSize.width < minWidth else { return }
        self.playlistSize = CGSize(width: minWidth, height: self.playlistSize.height)
    }

    var isEqualizerDocked: Bool {
        self.showEqualizer && !self.isShadeMode
    }

    var playlistSizeBinding: Binding<CGSize> {
        Binding(
            get: { self.playlistSize },
            set: { self.playlistSize = $0 }
        )
    }

    var playlistMinimizedBinding: Binding<Bool> {
        Binding(
            get: { self.playlistMinimized },
            set: { self.playlistMinimized = $0 }
        )
    }
}

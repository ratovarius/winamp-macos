import SwiftUI

/// Layout state shared between the main window and detachable EQ / playlist panels.
@MainActor
final class WinampPanelLayoutState: ObservableObject {
    private static let playlistHeightKey = "playlistHeight"

    @Published var showEqualizer = true
    @Published var showPlaylist = true
    @Published var isShadeMode = false
    @Published var playlistMinimized = false
    @Published var playlistSize: CGSize {
        didSet {
            guard oldValue.height != self.playlistSize.height else { return }
            UserDefaults.standard.set(self.playlistSize.height, forKey: Self.playlistHeightKey)
        }
    }

    init() {
        let savedHeight = UserDefaults.standard.double(forKey: Self.playlistHeightKey)
        let height = savedHeight > 0 ? savedHeight : WinampMetrics.defaultPlaylistHeight
        self.playlistSize = CGSize(width: WinampUIScale.basePanelWidth, height: height)
    }

    func setPlaylistWidth(_ width: CGFloat) {
        guard self.playlistSize.width != width else { return }
        self.playlistSize = CGSize(width: width, height: self.playlistSize.height)
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

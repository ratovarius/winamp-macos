import Foundation

/// Routes playlist arrow-key navigation from `AppDelegate` into the visible `PlaylistView`.
@MainActor
enum WinampPlaylistKeyboard {
    private static weak var handler: Handling?

    static func register(_ handler: Handling) {
        self.handler = handler
    }

    static func unregister(_ handler: Handling) {
        if let current = self.handler as AnyObject?, let removing = handler as AnyObject?, current === removing {
            self.handler = nil
        }
    }

    static var isActive: Bool {
        self.handler != nil
    }

    static func moveSelection(by offset: Int) {
        self.handler?.moveSelection(by: offset)
    }

    static func playSelectedTrack() {
        self.handler?.playSelectedTrack()
    }
}

extension WinampPlaylistKeyboard {
    @MainActor
    protocol Handling: AnyObject {
        func moveSelection(by offset: Int)
        func playSelectedTrack()
    }
}

import AppKit

/// Shared borderless window chrome for main and panel windows.
@MainActor
enum WinampWindowConfigurator {
    static func apply(to window: NSWindow, resizable: Bool = true) {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable {
            styleMask.insert(.resizable)
        }
        window.styleMask = styleMask
        window.styleMask.remove(.borderless)

        window.collectionBehavior = []
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.backgroundColor = WinampColors.nsTitleBar
        window.isOpaque = true
        window.hasShadow = true
        window.isMovableByWindowBackground = false
    }
}

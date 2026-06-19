import AppKit
import SwiftUI

/// Classic Winamp skin sprite coordinates
/// Based on the standard Winamp Base skin layout
struct WinampSkinSprites: @unchecked Sendable {
    static let shared = WinampSkinSprites()

    /// Load the main skin image
    private let skinImage: NSImage? = NSImage(named: "WinampSkin")

    /// Main window components (from main.bmp coordinates)
    enum MainWindow {
        // Title bar
        static let titleBarActive = CGRect(x: 0, y: 0, width: 275, height: 14)
        static let titleBarInactive = CGRect(x: 0, y: 15, width: 275, height: 14)

        // Main buttons (Previous, Play, Pause, Stop, Next)
        static let buttonPrevious = CGRect(x: 0, y: 18, width: 23, height: 18)
        static let buttonPlay = CGRect(x: 23, y: 18, width: 23, height: 18)
        static let buttonPause = CGRect(x: 46, y: 18, width: 23, height: 18)
        static let buttonStop = CGRect(x: 69, y: 18, width: 23, height: 18)
        static let buttonNext = CGRect(x: 92, y: 18, width: 22, height: 18)
        static let buttonEject = CGRect(x: 114, y: 18, width: 22, height: 18)

        // Toggle buttons (EQ, PL, etc) - pressed and unpressed states
        static let buttonEQOff = CGRect(x: 0, y: 61, width: 23, height: 12)
        static let buttonEQOn = CGRect(x: 0, y: 73, width: 23, height: 12)
        static let buttonPLOff = CGRect(x: 23, y: 61, width: 23, height: 12)
        static let buttonPLOn = CGRect(x: 23, y: 73, width: 23, height: 12)

        // Shuffle and Repeat
        static let shuffleOff = CGRect(x: 28, y: 89, width: 47, height: 15)
        static let shuffleOn = CGRect(x: 28, y: 73, width: 47, height: 15)
        static let repeatOff = CGRect(x: 0, y: 89, width: 28, height: 15)
        static let repeatOn = CGRect(x: 0, y: 73, width: 28, height: 15)

        // Position bar
        static let posBarBackground = CGRect(x: 0, y: 36, width: 248, height: 10)
        static let posBarThumb = CGRect(x: 248, y: 36, width: 29, height: 10)

        // Volume/Balance sliders
        static let volumeSlider = CGRect(x: 0, y: 47, width: 68, height: 13)
        static let balanceSlider = CGRect(x: 9, y: 47, width: 38, height: 13)
    }

    enum Numbers {
        // LED-style numbers for time display
        static let digitWidth = 9
        static let digitHeight = 13
        // Numbers are typically at y: 26, x varies by digit
    }

    enum Visualizer {
        // Spectrum analyzer dots
        static let columns = 76
        static let height = 16
    }

    /// Helper to extract a sprite from the main skin image
    func getSprite(rect: CGRect) -> NSImage? {
        guard let skin = skinImage else { return nil }

        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()

        let destRect = NSRect(origin: .zero, size: rect.size)
        let sourceRect = NSRect(origin: rect.origin, size: rect.size)

        skin.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        croppedImage.unlockFocus()

        return croppedImage
    }

    /// Helper to create SwiftUI Image from sprite
    func getSpriteImage(rect: CGRect) -> Image? {
        guard let nsImage = getSprite(rect: rect) else { return nil }
        return Image(nsImage: nsImage)
    }
}

/// SwiftUI View for displaying skin sprites
struct SkinSpriteView: View {
    let rect: CGRect

    var body: some View {
        if let image = WinampSkinSprites.shared.getSpriteImage(rect: rect) {
            image
                .resizable()
                .interpolation(.none) // Pixel-perfect scaling
                .frame(width: self.rect.width, height: self.rect.height)
        }
    }
}

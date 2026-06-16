import AppKit
import SwiftUI

enum WinampColors {
    /// Classic Winamp 2.x "base" skin palette — slate blue-grey metallic chrome.
    static let background = Color(red: 0, green: 0, blue: 0)

    // Title bar colors (lighter steel-blue chrome with subtle pinstripe gradient)
    static let titleBar = Color(red: 60 / 255, green: 68 / 255, blue: 92 / 255)
    static let nsTitleBar = NSColor(red: 60 / 255, green: 68 / 255, blue: 92 / 255, alpha: 1)
    static let titleBarInactive = Color(red: 52 / 255, green: 56 / 255, blue: 70 / 255)
    static let titleBarHighlight = Color(red: 86 / 255, green: 94 / 255, blue: 118 / 255)

    // Display/LCD colors (dark with bright green text)
    static let displayBg = Color(red: 8 / 255, green: 20 / 255, blue: 16 / 255)
    static let displayText = Color(red: 0, green: 1.0, blue: 0.5)
    static let displayInactive = Color(red: 0, green: 0.3, blue: 0.2)

    // Main window background (slate blue-grey, the signature Winamp chrome)
    static let mainBg = Color(red: 74 / 255, green: 82 / 255, blue: 107 / 255)
    static let mainBgLight = Color(red: 92 / 255, green: 100 / 255, blue: 126 / 255)
    static let mainBgDark = Color(red: 52 / 255, green: 59 / 255, blue: 82 / 255)

    // Button colors (raised metallic blue-grey with crisp bevels)
    static let buttonFace = Color(red: 96 / 255, green: 104 / 255, blue: 128 / 255)
    static let buttonLight = Color(red: 150 / 255, green: 158 / 255, blue: 180 / 255)
    static let buttonDark = Color(red: 44 / 255, green: 50 / 255, blue: 70 / 255)
    static let buttonPressed = Color(red: 60 / 255, green: 66 / 255, blue: 88 / 255)
    static let buttonHover = Color(red: 110 / 255, green: 118 / 255, blue: 142 / 255)

    // Playlist colors — exact classic Winamp 2.91 base-skin PLEDIT.TXT values:
    // Normal=#00FF00, Current=#FFFFFF, NormalBG=#000000, SelectedBG=#0000C6.
    static let playlistBg = Color(red: 0, green: 0, blue: 0)
    static let playlistText = Color(red: 0, green: 1.0, blue: 0)
    static let playlistSelected = Color(red: 0, green: 0, blue: 0xC6 / 255) // #0000C6
    static let playlistCurrentTrack = Color.white
    static let playlistCurrentTrackBg = Color(red: 0, green: 0, blue: 0xC6 / 255)

    // Equalizer colors (classic Winamp orange/yellow gradient)
    static let eqSliderBg = Color(red: 20 / 255, green: 25 / 255, blue: 35 / 255)
    static let eqSliderGreen = Color(red: 0, green: 0.58, blue: 0.08)
    static let eqSliderYellow = Color(red: 0.95, green: 0.82, blue: 0.05)
    static let eqSliderOrange = Color(red: 1.0, green: 0.45, blue: 0.0)
    static let eqSliderRed = Color(red: 1.0, green: 0.12, blue: 0.05)
    static let eqSliderTop = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let eqSliderBottom = Color(red: 1.0, green: 0.4, blue: 0.0)
    static let eqCurve = Color(red: 1.0, green: 0.48, blue: 0.05)
    static let eqCurveHighlight = Color(red: 1.0, green: 0.72, blue: 0.18)
    static let eqFrame = Color(red: 60 / 255, green: 65 / 255, blue: 80 / 255)

    /// Maps a normalized level (0 = low/bottom/left, 1 = high/top/right) to the classic Winamp green→red scale.
    static func levelColor(normalized: CGFloat) -> Color {
        let n = max(0, min(1, normalized))
        if n <= 0.45 {
            let t = n / 0.45
            return Color(
                red: t * 0.95,
                green: 0.58 + t * 0.24,
                blue: 0.08 - t * 0.03
            )
        }
        if n <= 0.72 {
            let t = (n - 0.45) / 0.27
            return Color(
                red: 0.95 + t * 0.05,
                green: 0.82 - t * 0.37,
                blue: 0.05 + t * 0.0
            )
        }
        let t = (n - 0.72) / 0.28
        return Color(
            red: 1.0,
            green: 0.45 - t * 0.33,
            blue: 0.0 + t * 0.05
        )
    }

    // Spectrum/Visualizer
    static let spectrumBg = Color(red: 0, green: 0, blue: 0)
    static let spectrumDot = Color(red: 0, green: 1.0, blue: 0.5)
    static let spectrumPeak = Color(red: 1.0, green: 0, blue: 0)

    // Border colors (crisp metallic bevel highlights/shadows)
    static let borderLight = Color(red: 150 / 255, green: 158 / 255, blue: 180 / 255)
    static let borderDark = Color(red: 30 / 255, green: 35 / 255, blue: 50 / 255)
    static let borderAccent = Color(red: 70 / 255, green: 78 / 255, blue: 100 / 255)
}

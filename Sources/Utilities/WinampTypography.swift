import AppKit
import CoreText
import SwiftUI

enum WinampTypography {
    static let regularName = "JetBrains Mono"
    static let boldName = "JetBrainsMono-Bold"

    static func registerBundledFonts() {
        for resource in ["JetBrainsMono-Regular", "JetBrainsMono-Bold"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: resource, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static var isAvailable: Bool {
        NSFont(name: regularName, size: 12) != nil
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let bold = weight == .bold || weight == .semibold || weight == .heavy
        if isAvailable {
            let name = bold ? boldName : regularName
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
            return .custom(regularName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    static func nsFont(size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        let bold = weight == .bold || weight == .semibold || weight == .heavy
        let name = bold ? boldName : regularName
        if let custom = NSFont(name: name, size: size) {
            return custom
        }
        if let custom = NSFont(name: regularName, size: size) {
            return custom
        }
        return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

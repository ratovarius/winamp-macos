import SwiftUI

/// Classic Winamp LCD time readout rendered as 7-segment digits.
/// Lit segments glow green; unlit segments show as a dim ghost, matching the original.
struct SevenSegmentDisplay: View {
    /// Characters to render. Supports digits 0–9, ':', '-', and ' '.
    let text: String
    var digitWidth: CGFloat = 13
    var digitHeight: CGFloat = 20
    var spacing: CGFloat = 3
    var color: Color = WinampColors.displayText

    var body: some View {
        HStack(alignment: .center, spacing: self.spacing) {
            ForEach(Array(self.text.enumerated()), id: \.offset) { _, char in
                if char == ":" {
                    SevenSegmentColon(height: self.digitHeight, color: self.color)
                        .frame(width: self.digitWidth * 0.34, height: self.digitHeight)
                } else {
                    SevenSegmentDigit(character: char, color: self.color)
                        .frame(width: self.digitWidth, height: self.digitHeight)
                }
            }
        }
    }
}

private struct SevenSegmentColon: View {
    let height: CGFloat
    let color: Color

    var body: some View {
        VStack(spacing: self.height * 0.28) {
            Circle().fill(self.color).frame(width: self.height * 0.12)
            Circle().fill(self.color).frame(width: self.height * 0.12)
        }
        .shadow(color: self.color.opacity(0.6), radius: 1.5)
    }
}

private struct SevenSegmentDigit: View {
    let character: Character
    let color: Color

    // Segment map a,b,c,d,e,f,g (a=top, b=top-right, c=bottom-right, d=bottom,
    // e=bottom-left, f=top-left, g=middle).
    private static let segments: [Character: Set<Int>] = [
        "0": [0, 1, 2, 3, 4, 5],
        "1": [1, 2],
        "2": [0, 1, 6, 4, 3],
        "3": [0, 1, 2, 3, 6],
        "4": [5, 6, 1, 2],
        "5": [0, 5, 6, 2, 3],
        "6": [0, 5, 6, 4, 3, 2],
        "7": [0, 1, 2],
        "8": [0, 1, 2, 3, 4, 5, 6],
        "9": [0, 1, 2, 3, 5, 6],
        "-": [6],
        " ": [],
    ]

    var body: some View {
        Canvas { context, size in
            let lit = Self.segments[self.character] ?? []
            let w = size.width
            let h = size.height
            let t = min(w, h) * 0.16 // segment thickness
            let pad = t * 0.5
            let onColor = self.color
            let offColor = WinampColors.displayInactive.opacity(0.45)

            // Horizontal segment as a hexagon-ish bar.
            func horizontal(_ y: CGFloat) -> Path {
                var p = Path()
                let x0 = pad, x1 = w - pad
                p.move(to: CGPoint(x: x0 + t / 2, y: y))
                p.addLine(to: CGPoint(x: x1 - t / 2, y: y))
                p.addLine(to: CGPoint(x: x1, y: y + t / 2))
                p.addLine(to: CGPoint(x: x1 - t / 2, y: y + t))
                p.addLine(to: CGPoint(x: x0 + t / 2, y: y + t))
                p.addLine(to: CGPoint(x: x0, y: y + t / 2))
                p.closeSubpath()
                return p
            }

            func vertical(_ x: CGFloat, _ yTop: CGFloat, _ yBottom: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: x + t / 2, y: yTop))
                p.addLine(to: CGPoint(x: x + t, y: yTop + t / 2))
                p.addLine(to: CGPoint(x: x + t, y: yBottom - t / 2))
                p.addLine(to: CGPoint(x: x + t / 2, y: yBottom))
                p.addLine(to: CGPoint(x: x, y: yBottom - t / 2))
                p.addLine(to: CGPoint(x: x, y: yTop + t / 2))
                p.closeSubpath()
                return p
            }

            let midY = (h - t) / 2
            let paths: [(Int, Path)] = [
                (0, horizontal(pad)),                       // a top
                (1, vertical(w - pad - t, pad, midY + t)),  // b top-right
                (2, vertical(w - pad - t, midY, h - pad)),  // c bottom-right
                (3, horizontal(h - pad - t)),               // d bottom
                (4, vertical(pad, midY, h - pad)),          // e bottom-left
                (5, vertical(pad, pad, midY + t)),          // f top-left
                (6, horizontal(midY)),                      // g middle
            ]

            for (idx, path) in paths {
                let isLit = lit.contains(idx)
                context.fill(path, with: .color(isLit ? onColor : offColor))
            }
        }
        .shadow(color: self.color.opacity(0.5), radius: 2)
    }
}

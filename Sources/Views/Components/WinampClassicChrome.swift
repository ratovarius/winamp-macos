import SwiftUI

// MARK: - Classic title bar (pinstripe texture + beveled edge)

/// The signature Winamp 2.x title bar: a slate-blue gradient with horizontal
/// pinstripe lines drawn across the full width, a top highlight and bottom shadow.
/// Callers overlay the centered title and window buttons on top.
struct WinampTitleBarBackground: View {
    var body: some View {
        ZStack {
            WinampColors.titleBar

            // Fine horizontal pinstripe texture filling the full bar height.
            Canvas { context, size in
                let highlight = Color.white.opacity(0.30)
                let shadow = Color.black.opacity(0.28)
                var y: CGFloat = 2
                while y < size.height - 1 {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(highlight)
                    )
                    context.fill(
                        Path(CGRect(x: 0, y: y + 1, width: size.width, height: 1)),
                        with: .color(shadow)
                    )
                    y += 3
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.30)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1)
        }
    }
}

/// Small decorative notch ornament (cluster of vertical ticks) for title-bar ends.
struct WinampTitleBarOrnament: View {
    var ticks: Int = 6
    var height: CGFloat = 8

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< self.ticks, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1)
                    Rectangle().fill(Color.black.opacity(0.4)).frame(width: 1)
                }
            }
        }
        .frame(height: self.height)
    }
}

// MARK: - Classic 3D bevel chrome (Winamp 2.x base style)

struct WinampClassicBevel: View {
    let isPressed: Bool

    var body: some View {
        ZStack {
            (self.isPressed ? WinampColors.buttonPressed : WinampColors.buttonFace)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(self.isPressed ? WinampColors.buttonDark : WinampColors.buttonLight)
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(self.isPressed ? WinampColors.buttonLight : WinampColors.buttonDark)
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(self.isPressed ? WinampColors.buttonDark : WinampColors.buttonLight)
                    .frame(width: 1)
                Spacer()
                Rectangle()
                    .fill(self.isPressed ? WinampColors.buttonLight : WinampColors.buttonDark)
                    .frame(width: 1)
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
        )
    }
}

/// Flat silver/grey beveled button with dark text (PRESETS, ADD/REM/SEL/MISC, etc.).
struct WinampSilverTextButton: View {
    let title: String
    var scale: CGFloat = 1.0
    var minWidth: CGFloat = 30
    var height: CGFloat = WinampMetrics.smallButtonHeight
    var fontSize: CGFloat = 8
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            self.isPressed = true
            self.action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                self.isPressed = false
            }
        }) {
            Text(self.title)
                .winampFont(size: self.fontSize, weight: .bold, scale: self.scale)
                .foregroundColor(Color(red: 0.12, green: 0.13, blue: 0.18))
                .lineLimit(1)
                .padding(.horizontal, 5 * self.scale)
                .frame(height: self.height * self.scale)
                .frame(minWidth: self.minWidth * self.scale)
                .background(SilverBevel(isPressed: self.isPressed))
        }
        .buttonStyle(.plain)
    }
}

/// Large silver beveled transport key with a dark vector glyph (classic main-window buttons).
struct WinampTransportButton: View {
    enum Glyph { case prev, play, pause, stop, next, eject }

    let glyph: Glyph
    var width: CGFloat = 23
    var height: CGFloat = 18
    var scale: CGFloat = 1.0
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            self.isPressed = true
            self.action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                self.isPressed = false
            }
        }) {
            TransportGlyphShape(glyph: self.glyph)
                .fill(Color(red: 0.13, green: 0.15, blue: 0.20))
                .frame(width: self.width * 0.42 * self.scale, height: self.height * 0.5 * self.scale)
                .frame(width: self.width * self.scale, height: self.height * self.scale)
                .background(SilverBevel(isPressed: self.isPressed))
        }
        .buttonStyle(.plain)
    }
}

/// Raised silver/grey bevel used by transport keys (lighter than the blue chrome bevel).
struct SilverBevel: View {
    let isPressed: Bool

    var body: some View {
        let face = LinearGradient(
            colors: self.isPressed
                ? [Color(red: 0.62, green: 0.64, blue: 0.70), Color(red: 0.74, green: 0.76, blue: 0.81)]
                : [Color(red: 0.86, green: 0.88, blue: 0.92), Color(red: 0.62, green: 0.65, blue: 0.71)],
            startPoint: .top,
            endPoint: .bottom
        )
        ZStack {
            Rectangle().fill(face)

            VStack(spacing: 0) {
                Rectangle().fill(self.isPressed ? Color.black.opacity(0.35) : Color.white.opacity(0.9)).frame(height: 1)
                Spacer()
                Rectangle().fill(self.isPressed ? Color.white.opacity(0.5) : Color.black.opacity(0.45)).frame(height: 1)
            }
            HStack(spacing: 0) {
                Rectangle().fill(self.isPressed ? Color.black.opacity(0.35) : Color.white.opacity(0.9)).frame(width: 1)
                Spacer()
                Rectangle().fill(self.isPressed ? Color.white.opacity(0.5) : Color.black.opacity(0.45)).frame(width: 1)
            }
        }
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
    }
}

/// Vector glyphs for transport controls, drawn inside a unit-ish rect.
struct TransportGlyphShape: Shape {
    let glyph: WinampTransportButton.Glyph

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        switch self.glyph {
        case .play:
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + w, y: y + h / 2))
            p.addLine(to: CGPoint(x: x, y: y + h))
            p.closeSubpath()
        case .pause:
            let bar = w * 0.36
            p.addRect(CGRect(x: x, y: y, width: bar, height: h))
            p.addRect(CGRect(x: x + w - bar, y: y, width: bar, height: h))
        case .stop:
            p.addRect(rect)
        case .prev:
            // bar + two left triangles
            let bar = w * 0.16
            p.addRect(CGRect(x: x, y: y, width: bar, height: h))
            let t = (w - bar) / 2
            p.move(to: CGPoint(x: x + bar + t, y: y))
            p.addLine(to: CGPoint(x: x + bar, y: y + h / 2))
            p.addLine(to: CGPoint(x: x + bar + t, y: y + h))
            p.closeSubpath()
            p.move(to: CGPoint(x: x + w, y: y))
            p.addLine(to: CGPoint(x: x + bar + t, y: y + h / 2))
            p.addLine(to: CGPoint(x: x + w, y: y + h))
            p.closeSubpath()
        case .next:
            let bar = w * 0.16
            p.addRect(CGRect(x: x + w - bar, y: y, width: bar, height: h))
            let t = (w - bar) / 2
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + t, y: y + h / 2))
            p.addLine(to: CGPoint(x: x, y: y + h))
            p.closeSubpath()
            p.move(to: CGPoint(x: x + t, y: y))
            p.addLine(to: CGPoint(x: x + 2 * t, y: y + h / 2))
            p.addLine(to: CGPoint(x: x + t, y: y + h))
            p.closeSubpath()
        case .eject:
            // triangle pointing up + a base bar
            let barH = h * 0.28
            p.move(to: CGPoint(x: x, y: y + h - barH * 1.6))
            p.addLine(to: CGPoint(x: x + w / 2, y: y))
            p.addLine(to: CGPoint(x: x + w, y: y + h - barH * 1.6))
            p.closeSubpath()
            p.addRect(CGRect(x: x, y: y + h - barH, width: w, height: barH))
        }
        return p
    }
}

struct WinampClassicTextButton: View {
    let title: String
    var scale: CGFloat = 1.0
    var minWidth: CGFloat = 30
    var height: CGFloat = WinampMetrics.smallButtonHeight
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            self.isPressed = true
            self.action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                self.isPressed = false
            }
        }) {
            Text(self.title)
                .winampFont(size: 8, weight: .bold, scale: self.scale)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 4 * self.scale)
                .frame(height: self.height * self.scale)
                .frame(minWidth: self.minWidth * self.scale)
                .background(WinampClassicBevel(isPressed: self.isPressed))
                .offset(y: self.isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
    }
}

struct WinampClassicToggleButton: View {
    let title: String
    @Binding var isOn: Bool
    var width: CGFloat
    var scale: CGFloat = 1.0
    var height: CGFloat = WinampMetrics.smallButtonHeight

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            self.isOn.toggle()
        }) {
            ZStack(alignment: .bottomTrailing) {
                Text(self.title)
                    .winampFont(size: 8, weight: .bold, scale: self.scale)
                    .foregroundColor(.white.opacity(self.isOn ? 1.0 : 0.75))
                    .frame(width: self.width * self.scale, height: self.height * self.scale)

                Rectangle()
                    .fill(self.isOn ? WinampColors.displayText : Color(red: 0.1, green: 0.12, blue: 0.16))
                    .frame(width: 4 * self.scale, height: 4 * self.scale)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.black.opacity(0.6), lineWidth: 0.5)
                    )
                    .offset(x: -2 * self.scale, y: -1 * self.scale)
            }
            .background(WinampClassicBevel(isPressed: self.isPressed))
            .offset(y: self.isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in self.isPressed = true }
                .onEnded { _ in self.isPressed = false }
        )
    }
}

// MARK: - Skin-sprite buttons (bitmap-accurate transport / toggles)

struct WinampSkinButton: View {
    let sprite: CGRect
    var scale: CGFloat = 1.0
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            self.isPressed = true
            self.action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                self.isPressed = false
            }
        }) {
            SkinSpriteView(rect: self.sprite)
                .frame(width: self.sprite.width * self.scale, height: self.sprite.height * self.scale)
                .opacity(self.isPressed ? 0.85 : 1.0)
                .offset(y: self.isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
    }
}

struct WinampSkinToggle: View {
    let offSprite: CGRect
    let onSprite: CGRect
    @Binding var isOn: Bool
    var scale: CGFloat = 1.0

    @State private var isPressed = false

    private var activeSprite: CGRect {
        self.isOn ? self.onSprite : self.offSprite
    }

    var body: some View {
        Button(action: { self.isOn.toggle() }) {
            SkinSpriteView(rect: self.activeSprite)
                .frame(width: self.activeSprite.width * self.scale, height: self.activeSprite.height * self.scale)
                .offset(y: self.isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in self.isPressed = true }
                .onEnded { _ in self.isPressed = false }
        )
    }
}

// MARK: - Outer window frame (raised bevel around full panel stack)

/// Classic raised outer bevel framing a Winamp window or detached panel.
struct WinampOuterFrameModifier: ViewModifier {
    /// When true, height follows an explicit `.frame(height:)` instead of intrinsic content size.
    var flexibleVertical: Bool = false

    func body(content: Content) -> some View {
        Group {
            if self.flexibleVertical {
                content.fixedSize(horizontal: true, vertical: false)
            } else {
                content.fixedSize()
            }
        }
        .background(WinampColors.titleBar)
        .overlay(
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            WinampColors.borderLight.opacity(0.9),
                            WinampColors.borderLight.opacity(0.3),
                            WinampColors.borderDark.opacity(0.5),
                            WinampColors.borderDark.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }
}

extension View {
    func winampOuterFrame(flexibleVertical: Bool = false) -> some View {
        self.modifier(WinampOuterFrameModifier(flexibleVertical: flexibleVertical))
    }
}

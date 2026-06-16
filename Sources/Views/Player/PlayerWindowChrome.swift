import AppKit
import SwiftUI

enum WinampTitleBarMetrics {
    static let buttonAreaWidth: CGFloat = 60
}

final class DraggableWindowView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let locationInView = self.convert(event.locationInWindow, from: nil)
        if self.isInButtonArea(locationInView) {
            self.nextResponder?.mouseDown(with: event)
            return
        }

        if event.clickCount == 2 {
            WinampPanelWindowManager.shared.toggleWindowshade(for: window)
            return
        }
        WinampPanelWindowManager.shared.startDrag(leading: window, event: event)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self.isInButtonArea(point) ? nil : self
    }

    private func isInButtonArea(_ point: NSPoint) -> Bool {
        guard self.bounds.width > 0 else { return false }
        let buttonAreaStart = self.bounds.width - WinampTitleBarMetrics.buttonAreaWidth
        return point.x > buttonAreaStart && point.x >= 0 && point.x <= self.bounds.width
    }
}

/// SwiftUI wrapper for the draggable view
struct DraggableWindowViewRepresentable: NSViewRepresentable {
    func makeNSView(context _: Context) -> DraggableWindowView {
        let view = DraggableWindowView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_: DraggableWindowView, context _: Context) {}
}

struct ClassicTitleBar: View {
    @Binding var isShadeMode: Bool
    @Environment(\.winampUIScale) private var uiScale

    var body: some View {
        HStack(spacing: 6) {
            Spacer()

            WinampTitleBarOrnament(ticks: 8, height: 7 * uiScale)

            Text("WINAMP")
                .winampFont(size: 10, weight: .bold, scale: uiScale)
                .foregroundColor(.white)
                .tracking(2)
                .padding(.horizontal, 6)
                .background(WinampColors.titleBar)

            WinampTitleBarOrnament(ticks: 8, height: 7 * uiScale)

            Spacer()

            HStack(spacing: 2) {
                ModernWindowButton(icon: "○", tooltip: "Minimize", action: .minimize, isShadeMode: self.$isShadeMode)
                ModernWindowButton(icon: "▼", tooltip: "Shade", action: .shade, isShadeMode: self.$isShadeMode)
                ModernWindowButton(icon: "✕", tooltip: "Close", action: .close, isShadeMode: self.$isShadeMode)
            }
            .padding(.trailing, 4)
            .zIndex(1)
        }
        .padding(.horizontal, 8)
        .frame(height: WinampMetrics.titleBarHeight * uiScale)
        .frame(maxWidth: .infinity)
        .background(WinampTitleBarBackground())
        .overlay(alignment: .leading) {
            PanelTitleBarDragOverlay(excludedTrailingWidth: WinampTitleBarMetrics.buttonAreaWidth)
        }
    }
}

struct ModernWindowButton: View {
    let icon: String
    let tooltip: String
    let action: WindowControlAction
    @Binding var isShadeMode: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: self.performAction) {
            Text(self.icon)
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(self.isHovered ? .white : Color(red: 0.7, green: 0.7, blue: 0.7))
                .frame(width: 14, height: 12)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(self.isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(self.tooltip)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }

    func performAction() {
        switch self.action {
        case .minimize:
            self.activeWindow()?.miniaturize(nil)
        case .shade:
            self.isShadeMode.toggle()
        case .close:
            NSApplication.shared.terminate(nil)
        }
    }

    private func activeWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
    }
}

enum WindowControlAction {
    case minimize
    case shade
    case close
}

/// Drag handle overlay for EQ / playlist title bars (excludes trailing controls).
struct PanelTitleBarDragOverlay: View {
    var excludedTrailingWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            DraggableWindowViewRepresentable()
                .frame(width: max(0, geometry.size.width - excludedTrailingWidth))
        }
        .allowsHitTesting(true)
    }
}

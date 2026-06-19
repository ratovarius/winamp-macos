import AppKit
import SwiftUI

/// Tracks the playlist search field so clicks elsewhere or Escape restore playback shortcuts.
@MainActor
enum WinampPlaylistSearchFocus {
    static let containerIdentifier = NSUserInterfaceItemIdentifier("WinampSearchFieldContainer")

    private static weak var activeField: ClickToFocusSearchField?

    fileprivate static func registerActive(_ field: ClickToFocusSearchField) {
        self.activeField = field
    }

    fileprivate static func unregisterActive(_ field: ClickToFocusSearchField) {
        if self.activeField === field {
            self.activeField = nil
        }
    }

    static var isActive: Bool {
        self.activeField != nil
    }

    static func contains(_ view: NSView?) -> Bool {
        var current = view
        while let view = current {
            if view is ClickToFocusSearchField || view.identifier == self.containerIdentifier {
                return true
            }
            current = view.superview
        }
        return false
    }

    static func dismissActive() {
        guard let field = self.activeField, let window = field.window else { return }
        window.makeFirstResponder(nil)
    }

    static func handleClick(at hitView: NSView?) {
        guard self.isActive, !self.contains(hitView) else { return }
        self.dismissActive()
    }
}

/// Avoids stealing keyboard focus when the window first opens; click to edit.
private final class ClickToFocusSearchField: NSTextField {
    private var userRequestedFocus = false

    override var acceptsFirstResponder: Bool {
        self.userRequestedFocus
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            WinampPlaylistSearchFocus.registerActive(self)
        }
        return became
    }

    override func mouseDown(with event: NSEvent) {
        self.userRequestedFocus = true
        self.window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            self.userRequestedFocus = false
            WinampPlaylistSearchFocus.unregisterActive(self)
        }
        return resigned
    }
}

/// Inset LCD-style search field without the macOS blue focus ring.
struct WinampSearchField: NSViewRepresentable {
    @Binding var text: String
    var scale: CGFloat = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.identifier = WinampPlaylistSearchFocus.containerIdentifier

        let field = ClickToFocusSearchField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search..."
        field.delegate = context.coordinator
        field.font = WinampTypography.nsFont(size: 9 * self.scale)
        field.textColor = NSColor(WinampColors.displayText)
        field.placeholderAttributedString = NSAttributedString(
            string: "Search...",
            attributes: [
                .foregroundColor: NSColor(WinampColors.displayInactive),
                .font: WinampTypography.nsFont(size: 9 * self.scale),
            ]
        )
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4 * self.scale),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4 * self.scale),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        context.coordinator.field = field
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let field = context.coordinator.field else { return }
        if field.stringValue != self.text {
            field.stringValue = self.text
        }
        field.font = WinampTypography.nsFont(size: 9 * self.scale)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        weak var field: NSTextField?

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            self.text = field.stringValue
        }
    }
}

struct WinampSearchBar: View {
    @Binding var text: String
    var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(WinampColors.displayBg)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.black.opacity(0.95), WinampColors.borderDark.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            HStack(spacing: 4 * self.scale) {
                Text(">")
                    .winampFont(size: 9, weight: .bold, scale: self.scale)
                    .foregroundColor(WinampColors.displayText.opacity(0.7))

                WinampSearchField(text: self.$text, scale: self.scale)
                    .frame(maxWidth: .infinity)

                if !self.text.isEmpty {
                    Button(action: { self.text = "" }) {
                        Text("x")
                            .winampFont(size: 9, weight: .bold, scale: self.scale)
                            .foregroundColor(WinampColors.displayText.opacity(0.65))
                            .frame(width: 12 * self.scale)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4 * self.scale)
        }
        .frame(height: WinampMetrics.playlistSearchHeight * self.scale)
    }
}

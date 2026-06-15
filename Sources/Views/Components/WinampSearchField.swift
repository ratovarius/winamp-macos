import AppKit
import SwiftUI

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

        let field = NSTextField(string: "")
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

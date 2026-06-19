import AppKit
import SwiftUI

/// Raised inset panel chrome used in shade mode readouts and mini visualizer.
struct ShadeInsetPanel<Content: View>: View {
    var fillColor: Color = .black
    @ViewBuilder var content: () -> Content

    var body: some View {
        self.content()
            .background(
                ZStack {
                    self.fillColor
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.black.opacity(0.8), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .cornerRadius(3)
            .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
}

/// Dark song-title inset used in shade mode (slightly lighter than LCD black).
struct ShadeSongInsetPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ShadeInsetPanel(fillColor: Color(red: 0.1, green: 0.12, blue: 0.18), content: self.content)
    }
}

import AppKit
import SwiftUI

struct MilkdropVisualizerView: View {
    @State private var currentPreset: VisualizationPreset = .kaleidoscope
    @State private var autoChangeTimer: Timer?
    @State private var fadeOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: self.previousPreset) {
                    Text("◀")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)

                Text("MILKDROP • \(self.currentPreset.name)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)

                Spacer()

                Button(action: self.nextPreset) {
                    Text("▶")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.2, blue: 0.35),
                        Color(red: 0.1, green: 0.15, blue: 0.25),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            MilkdropMetalVisualizationView(preset: self.currentPreset)
                .opacity(self.fadeOpacity)
                .background(Color.black)
        }
        .background(Color.black)
        .onAppear {
            self.startAutoChangeTimer()
        }
        .onDisappear {
            self.stopAutoChangeTimer()
        }
    }

    private func nextPreset() {
        self.stopAutoChangeTimer()
        self.changePresetWithFade(direction: 1)
        self.startAutoChangeTimer()
    }

    private func previousPreset() {
        self.stopAutoChangeTimer()
        self.changePresetWithFade(direction: -1)
        self.startAutoChangeTimer()
    }

    private func changePresetWithFade(direction: Int) {
        withAnimation(.easeOut(duration: 0.5)) {
            self.fadeOpacity = 0.0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.currentPreset = self.currentPreset.advanced(by: direction)

            withAnimation(.easeIn(duration: 0.5)) {
                self.fadeOpacity = 1.0
            }
        }
    }

    private func startAutoChangeTimer() {
        self.autoChangeTimer?.invalidate()
        self.autoChangeTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.changePresetWithFade(direction: 1)
            }
        }
    }

    private func stopAutoChangeTimer() {
        self.autoChangeTimer?.invalidate()
        self.autoChangeTimer = nil
    }
}

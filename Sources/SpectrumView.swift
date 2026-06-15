import SwiftUI

// MARK: - Visualization Mode

enum VisualizationMode: Int {
    case bars = 0
    case oscilloscope = 1

    static func from(storageValue: Int) -> VisualizationMode {
        storageValue == 0 ? .bars : .oscilloscope
    }

    var storageValue: Int {
        rawValue
    }

    func toggled() -> VisualizationMode {
        self == .bars ? .oscilloscope : .bars
    }
}

// MARK: - Metal mini visualizer (spectrum / oscilloscope)

struct ClassicVisualizerView: View {
    @AppStorage("visualizationMode") private var visualizationModeRaw: Int = 0

    private var visualizationMode: VisualizationMode {
        VisualizationMode.from(storageValue: self.visualizationModeRaw)
    }

    var body: some View {
        MetalVisualizationView(visualizationMode: self.visualizationMode)
            .background(Color.black)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    let newMode = self.visualizationMode.toggled()
                    self.visualizationModeRaw = newMode.storageValue
                }
            }
    }
}

struct SpectrumView: View {
    var body: some View {
        ClassicVisualizerView()
    }
}

struct SpectrumBar: View {
    let value: Float
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            WinampColors.spectrumDot,
                            WinampColors.spectrumDot.opacity(0.7),
                            WinampColors.spectrumDot.opacity(0.4),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: CGFloat(self.value) * self.height * 0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

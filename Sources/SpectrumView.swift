import SwiftUI

// MARK: - Visualization Mode

enum VisualizationMode: Int, CaseIterable {
    case bars = 0
    case oscilloscope = 1
    case analyzer = 2

    static func from(storageValue: Int) -> VisualizationMode {
        let count = Self.allCases.count
        let index = ((storageValue % count) + count) % count
        return Self.allCases[index]
    }

    var storageValue: Int {
        rawValue
    }

    func advanced() -> VisualizationMode {
        let all = Self.allCases
        let next = (self.rawValue + 1) % all.count
        return all[next]
    }
}

// MARK: - Metal mini visualizer (spectrum / oscilloscope)

struct ClassicVisualizerView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayer
    @AppStorage("visualizationMode") private var visualizationModeRaw: Int = 0

    private var visualizationMode: VisualizationMode {
        VisualizationMode.from(storageValue: self.visualizationModeRaw)
    }

    var body: some View {
        MetalVisualizationView(
            visualizationMode: self.visualizationMode,
            isPlaying: self.audioPlayer.isPlaying
        )
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            let newMode = self.visualizationMode.advanced()
            self.visualizationModeRaw = newMode.storageValue
        }
    }
}

struct SpectrumView: View {
    var body: some View {
        ClassicVisualizerView()
    }
}

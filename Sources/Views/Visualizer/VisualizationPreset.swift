import Foundation

enum VisualizationPreset: Int, CaseIterable {
    case spiralGalaxy = 0
    case oscillatorGrid = 1
    case plasmaField = 2
    case particleStorm = 3
    case frequencyRings = 4
    case waveformTunnel = 5
    case kaleidoscope = 6
    case lfoMorph = 7
    case nebulaGalaxy = 8
    case starfieldFlight = 9
    case starWarsCrawl = 10

    var name: String {
        switch self {
        case .spiralGalaxy: "Spiral Galaxy"
        case .oscillatorGrid: "Oscillator Grid"
        case .plasmaField: "Plasma Field"
        case .particleStorm: "Particle Storm"
        case .frequencyRings: "Frequency Rings"
        case .waveformTunnel: "Waveform Tunnel"
        case .kaleidoscope: "Kaleidoscope"
        case .lfoMorph: "LFO Morph"
        case .nebulaGalaxy: "Nebula Galaxy"
        case .starfieldFlight: "Starfield Flight"
        case .starWarsCrawl: "Star Wars Crawl"
        }
    }

    func advanced(by step: Int) -> VisualizationPreset {
        let all = VisualizationPreset.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        let count = all.count
        let newIndex = ((index + step) % count + count) % count
        return all[newIndex]
    }
}

import Foundation

/// A fullscreen ("Milkdrop"-style) visualization preset.
///
/// Each case maps 1:1 to a distinct branch in `fullscreenFragment` (VisualizerShaders.metal),
/// dispatched by `rawValue` with no wraparound. The shader contract is: implement exactly one
/// branch per case, in raw-value order. `VisualizationPresetTests` guards the count so adding a
/// case here without a matching shader branch fails a test rather than silently aliasing.
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

    /// Number of distinct shader branches `fullscreenFragment` must implement. Single source of
    /// truth shared (by assertion) with the `.metal` dispatch.
    static let shaderBranchCount = allCases.count

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

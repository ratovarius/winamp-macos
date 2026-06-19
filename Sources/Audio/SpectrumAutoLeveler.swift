import Foundation

/// Adaptive display range so quiet material still produces visible motion.
struct SpectrumAutoLeveler: Sendable {
    private static let minimumRange: Float = 0.02
    private static let ceilingDecayPerSecond: Float = 1.8
    private static let floorRisePerSecond: Float = 0.35

    private var noiseFloor: Float = 0.02
    private var signalCeiling: Float = 0.25

    mutating func normalize(_ bands: [Float]) -> [Float] {
        guard !bands.isEmpty else { return bands }

        let peak = bands.max() ?? 0
        if peak > self.signalCeiling {
            self.signalCeiling = peak
        } else {
            self.signalCeiling = max(peak, self.signalCeiling - Self.ceilingDecayPerSecond * 0.02)
        }

        let quietSlice = bands.sorted().prefix(max(1, bands.count / 8))
        let quietAverage = quietSlice.reduce(0, +) / Float(quietSlice.count)
        let proposedFloor = max(0.001, quietAverage * 1.1)
        self.noiseFloor = min(
            self.noiseFloor + Self.floorRisePerSecond * 0.02,
            min(proposedFloor, peak * 0.9)
        )

        let range = max(self.signalCeiling - self.noiseFloor, Self.minimumRange)
        return bands.map { value in
            min(1, max(0, (value - self.noiseFloor) / range))
        }
    }

    mutating func reset() {
        self.noiseFloor = 0.02
        self.signalCeiling = 0.25
    }
}

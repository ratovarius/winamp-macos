import Foundation
import os

private let spectrumDebugLogger = Logger(subsystem: "com.winamp.macos", category: "SpectrumDebug")

/// Throttled spectrum diagnostics for Console.app (`SpectrumDebug` category).
enum SpectrumAnalyzerDebugProbe: Sendable {
    #if DEBUG
    nonisolated(unsafe) static var isEnabled = true
    #else
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "SpectrumDebugLogging")
    }
    #endif

    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastLogTime: CFAbsoluteTime = 0
    private static let minimumInterval: CFAbsoluteTime = 1.0

    static func log(stage: String, bands: [Float], context: String = "") {
        guard self.isEnabled, !bands.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        defer { self.lock.unlock() }
        guard now - self.lastLogTime >= self.minimumInterval else { return }
        self.lastLogTime = now

        let stride = max(1, bands.count / 8)
        let sample = Swift.stride(from: 0, to: bands.count, by: stride).map { bands[$0] }
        let minValue = bands.min() ?? 0
        let maxValue = bands.max() ?? 0
        let mean = bands.reduce(0, +) / Float(bands.count)
        let suffix = context.isEmpty ? "" : " \(context)"

        spectrumDebugLogger.info(
            """
            \(stage, privacy: .public): min=\(minValue, privacy: .public) max=\(maxValue, privacy: .public) \
            mean=\(mean, privacy: .public) sample=\(sample.description, privacy: .public)\(suffix, privacy: .public)
            """
        )
    }
}

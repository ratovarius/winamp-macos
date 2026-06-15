import AppKit
import QuartzCore

enum VisualizationDisplayTiming {
    static func preferredFramesPerSecond(for screen: NSScreen? = NSScreen.main) -> Int {
        self.preferredFramesPerSecond(maximumFramesPerSecond: screen.map { Double($0.maximumFramesPerSecond) })
    }

    static func preferredFramesPerSecond(maximumFramesPerSecond: Double?) -> Int {
        guard let maxFPS = maximumFramesPerSecond, maxFPS > 60 else { return 60 }
        return min(Int(maxFPS), 120)
    }
}

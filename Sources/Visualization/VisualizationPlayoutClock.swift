import Foundation

/// Pure mapping from elapsed wall-clock time to a position within a batch of
/// intra-buffer analysis frames.
///
/// The macOS audio tap delivers ~100 ms buffers only ~10 times per second, yet
/// each buffer already contains many short FFT hop-frames of detail. Showing one
/// frame per buffer makes the visualizer step at 10 Hz. This clock "plays out"
/// the per-buffer frames across the buffer's wall-clock duration so a display
/// loop running at 60–120 Hz can sample genuinely different frames over time.
enum VisualizationPlayoutClock {
    /// Returns the frame index to display at `now` for a batch that arrived at
    /// `batchArrival` and spans `batchDuration` seconds.
    ///
    /// - The index advances linearly from `0` at arrival to the last frame at
    ///   `batchArrival + batchDuration`, then holds on the last frame so a late
    ///   follow-up buffer simply freezes the newest detail rather than snapping
    ///   backwards.
    /// - A non-positive `batchDuration` (e.g. a single-frame publish) always maps
    ///   to the newest frame, which keeps the single-shot publish path exact.
    static func frameIndex(
        now: Double,
        batchArrival: Double,
        frameCount: Int,
        batchDuration: Double
    ) -> Int {
        guard frameCount > 1 else { return max(frameCount - 1, 0) }
        guard batchDuration > 0 else { return frameCount - 1 }

        let elapsed = now - batchArrival
        if elapsed <= 0 { return 0 }

        let interval = batchDuration / Double(frameCount)
        let index = Int(elapsed / interval)
        return min(max(index, 0), frameCount - 1)
    }
}

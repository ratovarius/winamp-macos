import QuartzCore

/// Monotonic time source for the visualizer's frame timing. Production uses
/// `CACurrentMediaTime()`; tests inject a deterministic fake so frame pacing can be
/// verified without a GPU or real elapsed time.
protocol VisualizationClock: Sendable {
    func now() -> CFTimeInterval
}

/// Default clock backed by `CACurrentMediaTime()` (a monotonic, display-link-aligned timebase).
struct MediaTimeClock: VisualizationClock {
    func now() -> CFTimeInterval { CACurrentMediaTime() }
}

/// Per-frame elapsed/delta timekeeping for the render loop, driven by an injectable
/// `VisualizationClock`.
///
/// Extracting this removes the renderer's hidden dependency on `CACurrentMediaTime()`: the
/// time source is now explicit and overridable, and the (otherwise GPU-bound) frame pacing is
/// unit-testable. The math is a faithful copy of the renderer's previous inline timing — one
/// clock read per tick yields both the elapsed-since-start and delta-since-last-frame values.
struct RenderFrameClock {
    private let clock: VisualizationClock
    private var startTime: CFTimeInterval
    private var lastFrameTime: CFTimeInterval

    init(clock: VisualizationClock = MediaTimeClock()) {
        self.clock = clock
        let now = clock.now()
        self.startTime = now
        self.lastFrameTime = now
    }

    /// Advances to the current time, returning the raw clock value, seconds since the clock was
    /// created, and seconds since the previous `tick`. The delta is intentionally unclamped —
    /// downstream consumers (the feature smoother, peak tracker, history decay) clamp as needed,
    /// matching the renderer's prior behavior.
    mutating func tick() -> (now: CFTimeInterval, elapsed: CFTimeInterval, delta: CFTimeInterval) {
        let now = self.clock.now()
        let delta = now - self.lastFrameTime
        self.lastFrameTime = now
        return (now, now - self.startTime, delta)
    }

    /// Resets the delta baseline to "now" without moving the start epoch, so the first frame
    /// after an idle pause reports a small delta instead of the whole paused span.
    mutating func resetDelta() {
        self.lastFrameTime = self.clock.now()
    }
}

import QuartzCore

/// Decides when an audio-reactive visualizer may pause its display loop.
///
/// A mini visualizer goes completely static once playback stops and the bars/afterglow
/// have decayed, yet `MTKView` keeps redrawing at the display rate. This gate watches a
/// per-frame "active" signal and, after a short settle window (so the persistence
/// afterglow finishes fading on screen before the last frame freezes), reports that the
/// loop can be paused. It is pure and frame-rate independent so it can be unit-tested
/// without a GPU.
struct VisualizerIdleGate: Sendable {
    /// How long activity must stay below threshold before pausing. Sized to outlast the
    /// spectrum persistence afterglow (~0.8 s) so the frozen frame is already cleared.
    private let holdDuration: CFTimeInterval

    private(set) var idleElapsed: CFTimeInterval = 0
    private(set) var isPaused = false

    init(holdDuration: CFTimeInterval = 1.0) {
        self.holdDuration = holdDuration
    }

    /// Advances the gate by one frame and returns whether the loop should be paused now.
    /// - Parameters:
    ///   - isActive: `true` while playing or while any visible energy remains.
    ///   - deltaTime: seconds since the previous frame.
    @discardableResult
    mutating func update(isActive: Bool, deltaTime: CFTimeInterval) -> Bool {
        if isActive {
            self.idleElapsed = 0
            self.isPaused = false
        } else if !self.isPaused {
            self.idleElapsed += max(0, deltaTime)
            if self.idleElapsed >= self.holdDuration {
                self.isPaused = true
            }
        }
        return self.isPaused
    }

    /// Forces the gate back awake (e.g. playback resumed). The next `update` starts a fresh
    /// idle window.
    mutating func wake() {
        self.idleElapsed = 0
        self.isPaused = false
    }
}

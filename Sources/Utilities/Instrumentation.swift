import os

/// Centralized `os_signpost` instrumentation for the performance-critical paths
/// (audio analysis and visualization rendering).
///
/// Intervals and events surface in Instruments under the **os_signpost** /
/// **Points of Interest** track, so per-frame CPU cost, GPU execution time, and
/// audio-analysis cadence can be measured directly — no bespoke `print` probes.
///
/// Usage: profile a Release/Debug build with the *Time Profiler* + *os_signpost*
/// templates; filter by subsystem `com.winamp.macos`.
enum Instrumentation {
    static let subsystem = "com.winamp.macos"

    /// Audio analysis path: FFT hop processing and feature publishing.
    static let audio = OSSignposter(subsystem: subsystem, category: "Audio")

    /// Visualization render loop: per-frame CPU encoding and GPU execution time.
    static let visualization = OSSignposter(subsystem: subsystem, category: "Visualization")
}

import Foundation

/// Lightweight, explicitly-placed diagnostic logging for performance
/// investigations (audio data-rate, visualization refresh-rate, etc.).
///
/// Kept in the codebase on purpose: the call sites are cheap and easy to find
/// (search for "DiagnosticLog" or the `[TAG]` prefixes), so refresh-rate and
/// data-rate probes can be re-run without rebuilding the scaffolding each time.
/// Flip ``isEnabled`` to silence every call site at once.
enum DiagnosticLog {
    /// Master switch for all diagnostic call sites.
    static let isEnabled = true

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Wall-clock timestamp (`HH:mm:ss.mmm`) for correlating logs with playback.
    static func timestamp() -> String {
        self.timestampFormatter.string(from: Date())
    }

    /// `print` + flush. stdout is block-buffered when redirected to a file, so
    /// flushing keeps diagnostics live when capturing to a log.
    static func log(_ message: String) {
        guard self.isEnabled else { return }
        print(message)
        fflush(stdout)
    }
}

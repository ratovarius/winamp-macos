import Foundation

enum WinampTimeFormatting {
    static func format(_ time: TimeInterval, showNegative: Bool = false) -> String {
        let absTime = abs(time)
        let minutes = Int(absTime) / 60
        let seconds = Int(absTime) % 60
        let prefix = showNegative ? "-" : ""
        return String(format: "%@%d:%02d", prefix, minutes, seconds)
    }
}

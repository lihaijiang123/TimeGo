import Foundation

enum DurationFormat {
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let sign = total < 0 ? "-" : ""
        let absTotal = abs(total)
        let hours = absTotal / 3600
        let minutes = (absTotal % 3600) / 60
        let seconds = absTotal % 60
        if hours > 0 {
            return String(format: "%@%d:%02d:%02d", sign, hours, minutes, seconds)
        }
        return String(format: "%@%d:%02d", sign, minutes, seconds)
    }

    /// Compact `H:MM` without seconds.
    /// Rounds **up** to the next whole minute so a countdown never understates
    /// remaining time (e.g. 5:59 → `0:06`, 5:00 → `0:05`, 0:59 → `0:01`).
    static func short(_ interval: TimeInterval) -> String {
        let seconds = max(0, interval)
        let totalMinutes: Int
        if seconds <= 0 {
            totalMinutes = 0
        } else {
            // Ceil to whole minutes; tiny epsilon keeps exact multiples stable.
            totalMinutes = Int(ceil((seconds - 1e-9) / 60.0))
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let timeWithSeconds: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

import Foundation

/// Display formatting shared by the window, the status bar and the menu bar.
/// Sizes use binary units (1 KB = 1024 B).
public enum Format {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func bytes(_ value: Int64) -> String {
        if value < 0 { return "" }
        if value < 1024 { return "\(value) B" }
        var amount = Double(value)
        var unit = 0
        while amount >= 1024 && unit < units.count - 1 {
            amount /= 1024
            unit += 1
        }
        let digits = amount < 10 ? 2 : (amount < 100 ? 1 : 0)
        return String(format: "%.\(digits)f ", amount) + units[unit]
    }

    /// Blank when idle, so idle rows in the speed columns stay quiet.
    public static func rate(_ bytesPerSecond: Int) -> String {
        bytesPerSecond <= 0 ? "" : bytes(Int64(bytesPerSecond)) + "/s"
    }

    public static func rateOrZero(_ bytesPerSecond: Int) -> String {
        bytesPerSecond <= 0 ? "0 B/s" : rate(bytesPerSecond)
    }

    /// Short form for the menu bar: "1.2M", "340K".
    public static func compactRate(_ bytesPerSecond: Int) -> String {
        let value = Double(max(0, bytesPerSecond))
        if value >= 1024 * 1024 * 1024 { return String(format: "%.1fG", value / 1_073_741_824) }
        if value >= 1024 * 1024 { return String(format: "%.1fM", value / 1_048_576) }
        if value >= 1024 { return String(format: "%.0fK", value / 1024) }
        return String(format: "%.0fB", value)
    }

    public static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return "∞" }
        let total = max(0, Int(seconds.rounded()))
        let years = total / 31_536_000
        let weeks = (total % 31_536_000) / 604_800
        let days = (total % 604_800) / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if years > 0 { return "\(years)y \(weeks)w" }
        if weeks > 0 { return "\(weeks)w \(days)d" }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    public static func ratio(_ value: Double) -> String {
        if value.isInfinite { return "∞" }
        return String(format: "%.3f", value)
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.1f %%", fraction * 100)
    }

    /// "12 (340)": connected, then the swarm total from trackers when known.
    public static func count(_ connected: Int, of swarm: Int) -> String {
        swarm >= 0 ? "\(connected) (\(swarm))" : "\(connected)"
    }

    public static func availability(_ value: Double) -> String {
        value < 0 ? "" : String(format: "%.3f", value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    public static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateFormatter.string(from: date)
    }
}

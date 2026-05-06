import Foundation

enum GeeAgentTimeFormatting {
    static func conversationTimestampLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "--"
        }

        let lowered = trimmed.lowercased()
        if lowered == "now" || lowered == "just now" {
            return "Just now"
        }

        guard let date = parseTimestamp(trimmed) else {
            return trimmed
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < -60 {
            return absoluteTimestampLabel(date)
        }

        if interval < 60 {
            return "Just now"
        }

        if interval < 3_600 {
            return "\(max(Int(interval / 60), 1))m ago"
        }

        if interval < 86_400 {
            return "\(max(Int(interval / 3_600), 1))h ago"
        }

        if interval < 604_800 {
            let days = max(Int(interval / 86_400), 1)
            let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3_600)
            return hours > 0 ? "\(days)d \(hours)h ago" : "\(days)d ago"
        }

        return absoluteTimestampLabel(date)
    }

    static func absoluteTimestampLabel(_ raw: String) -> String {
        guard let date = parseTimestamp(raw) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return absoluteTimestampLabel(date)
    }

    static func absoluteTimestampLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

}

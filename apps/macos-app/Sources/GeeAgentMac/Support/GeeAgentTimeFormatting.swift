import Foundation

enum GeeAgentTimeFormatting {
    static func conversationTimestampLabel(
        _ raw: String,
        language: AppLanguage = AppLanguage.savedPreference()
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "--"
        }

        let lowered = trimmed.lowercased()
        if lowered == "now" || lowered == "just now" {
            return AppLocalization.string("time.justNow", defaultValue: "Just now", language: language)
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
            return AppLocalization.string("time.justNow", defaultValue: "Just now", language: language)
        }

        if interval < 3_600 {
            return AppLocalization.format(
                "time.minutesAgo",
                defaultValue: "%dm ago",
                language: language,
                max(Int(interval / 60), 1)
            )
        }

        if interval < 86_400 {
            return AppLocalization.format(
                "time.hoursAgo",
                defaultValue: "%dh ago",
                language: language,
                max(Int(interval / 3_600), 1)
            )
        }

        if interval < 604_800 {
            let days = max(Int(interval / 86_400), 1)
            let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3_600)
            if hours > 0 {
                return AppLocalization.format(
                    "time.daysHoursAgo",
                    defaultValue: "%dd %dh ago",
                    language: language,
                    days,
                    hours
                )
            }
            return AppLocalization.format(
                "time.daysAgo",
                defaultValue: "%dd ago",
                language: language,
                days
            )
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

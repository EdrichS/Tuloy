import Foundation

/// Small text helpers for times and countdowns.
enum Format {
    /// "11:00 AM", or "Tue 11:00 AM" when it isn't today.
    static func time(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Today", "Tomorrow", or the day's name.
    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "3 h 12 min", "45 min", or "less than a minute": the countdown in words.
    static func duration(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
        return minutes >= 1 ? "\(minutes) min" : "less than a minute"
    }

    /// "4:59" over an hour, "45m" under, "<1m" at the end, "–" when there's nothing to count to.
    static func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "–" }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 60 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return minutes >= 1 ? "\(minutes)m" : "<1m"
    }
}

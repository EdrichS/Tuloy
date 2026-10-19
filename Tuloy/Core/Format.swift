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

    /// "Today", "Yesterday", or "Sat, 17 Oct": a heading for a day's pings.
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Today", "Tomorrow", or the day's name.
    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "8:00 PM" today, "5:00 AM tomorrow", otherwise "Wed 5:00 AM".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(time) tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// How old a reading is: "just now", "6 min ago", or "as of 3:01 PM" once it's over 15 minutes.
    static func age(of date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 2 { return "just now" }
        if minutes <= 15 { return "\(minutes) min ago" }
        return "as of \(time(date))"
    }

    /// "3 h 12 min", "45 min", or "less than a minute": the countdown in words.
    static func duration(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
        return minutes >= 1 ? "\(minutes) min" : "less than a minute"
    }

    /// The Ultra icon's countdown, short enough to read inside the ring: whole hours ("5h", "4h",
    /// "3h") while more than two hours are left, then minutes from "120" down to "1". Rounded up,
    /// so it never says less time is left than there is. Days ("2d") for a rest that runs past 48 hours.
    static func ringCountdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "–" }
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes <= 120 { return "\(minutes)" }
        let hours = Int((Double(minutes) / 60).rounded(.up))
        if hours <= 48 { return "\(hours)h" }
        return "\(Int((Double(hours) / 24).rounded(.up)))d"
    }

    /// "4:59" over an hour, "45m" under, "<1m" at the end, "–" when there's nothing to count to.
    static func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "–" }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 60 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return minutes >= 1 ? "\(minutes)m" : "<1m"
    }
}

import Foundation

/// When you want fresh windows, and the pings that make them happen.
///
/// Claude's usage window starts with your first message and resets 5 hours
/// later. So for a fresh window at 11:00 AM, Tuloy pings at 6:00 AM.
struct Schedule: Equatable, Sendable {
    /// How long a Claude usage window lasts.
    static let window: TimeInterval = 5 * 60 * 60

    /// Pings go out a few seconds after the minute, so a slightly fast clock
    /// can't land one just before the time you meant.
    static let margin: TimeInterval = 15

    static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    /// When you want a fresh window, in minutes after midnight (660 = 11:00 AM).
    var freshMinutes = 11 * 60
    /// The days you want one, numbered the way Calendar does (1 = Sunday ... 7 = Saturday).
    var weekdays = Schedule.everyDay
    /// Keep going: after your fresh window, start a new one each time one ends.
    var keepGoing = false
    /// When keep going stops for the day, in minutes after midnight.
    var untilMinutes = 18 * 60

    // MARK: - The scheduled ping

    /// The next scheduled ping after `date`: 5 hours before your next fresh window.
    func nextPing(after date: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fresh = freshTime(onDayOf: day, calendar: calendar)
            else { continue }

            let ping = fresh.addingTimeInterval(Schedule.margin - Schedule.window)
            if ping > date { return ping }
        }
        return nil
    }

    /// Your next fresh window time after `date`.
    func nextFresh(after date: Date, calendar: Calendar = .current) -> Date? {
        nextPing(after: date.addingTimeInterval(Schedule.margin - Schedule.window), calendar: calendar)?
            .addingTimeInterval(Schedule.window - Schedule.margin)
    }

    /// Your fresh window time on the same day as `date`, or nil if that day is switched off.
    func freshTime(onDayOf date: Date, calendar: Calendar = .current) -> Date? {
        guard weekdays.contains(calendar.component(.weekday, from: date)) else { return nil }
        return time(freshMinutes, onDayOf: date, calendar: calendar)
    }

    // MARK: - Keep going

    /// Whether keep going may start a new window at `date`.
    func keepsGoing(at date: Date, calendar: Calendar = .current) -> Bool {
        guard keepGoing else { return false }

        // Never start a window that would still be open at your next scheduled ping:
        // it would push back the fresh window you asked for.
        if let next = nextPing(after: date, calendar: calendar), date.addingTimeInterval(Schedule.window) > next {
            return false
        }

        // A day's keep-going hours can run past midnight, so check yesterday's too.
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let fresh = freshTime(onDayOf: day, calendar: calendar)
            else { continue }

            if date >= fresh, date < stopTime(after: fresh, calendar: calendar) { return true }
        }
        return false
    }

    /// When keep going stops for the day whose fresh window is at `fresh`.
    func stopTime(after fresh: Date, calendar: Calendar = .current) -> Date {
        guard let sameDay = time(untilMinutes, onDayOf: fresh, calendar: calendar) else { return fresh }
        if sameDay > fresh { return sameDay }
        // A stop time at or before your fresh time means "after midnight".
        return calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
    }

    /// The windows Tuloy plans for the day whose fresh window is at `fresh`: the early
    /// one that ends right then, followed by one after another while keep going is on.
    func windows(endingFirstAt fresh: Date, calendar: Calendar = .current) -> [DateInterval] {
        var windows = [DateInterval(start: fresh.addingTimeInterval(-Schedule.window), duration: Schedule.window)]
        var start = fresh
        while windows.count < 6, keepsGoing(at: start, calendar: calendar) {
            windows.append(DateInterval(start: start, duration: Schedule.window))
            start.addTimeInterval(Schedule.window)
        }
        return windows
    }

    // MARK: - Text

    /// The daily ping time as text, e.g. "6:00 AM" for an 11:00 AM fresh window.
    var pingTimeText: String {
        let minutes = (freshMinutes - 5 * 60 + 24 * 60) % (24 * 60)
        let time = Schedule.text(forMinutes: minutes)
        return freshMinutes < 5 * 60 ? "\(time) the night before" : time
    }

    /// The whole schedule in a sentence or two.
    var summary: String {
        guard !weekdays.isEmpty else { return "Pick at least one day." }
        let first = "Tuloy pings Claude at \(pingTimeText), so your window resets right at \(freshTimeText)."
        guard keepGoing else { return first }
        return "\(first) From then on it starts a new window each time one ends, until \(untilTimeText)."
    }

    var freshTimeText: String { Schedule.text(forMinutes: freshMinutes) }
    var untilTimeText: String { Schedule.text(forMinutes: untilMinutes) }

    private static func text(forMinutes minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func time(_ minutes: Int, onDayOf date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: calendar.startOfDay(for: date))
    }
}

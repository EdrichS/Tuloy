import Foundation

/// What Tuloy knows about one of your limits: the 5-hour window, or the week.
struct UsageReading: Codable, Equatable, Sendable {
    /// How much you've used, 0 to 100. Nil if Claude Code didn't say.
    var percent: Int?
    /// When it resets.
    var resetsAt: Date
    /// When Tuloy learned this.
    var asOf: Date
    /// True when Tuloy worked out the reset time itself, because Claude Code didn't report one.
    var isEstimate = false

    /// Rounds a percentage and keeps it within 0...100.
    static func clampedPercent(_ value: Double) -> Int {
        min(100, max(0, Int(value.rounded())))
    }
}

/// One ping Tuloy sent, for History and the menu's "Recent Pings" list.
struct PingRecord: Codable, Equatable, Sendable {
    /// Why it was sent: on schedule, by keep going, or by you with "Ping Now".
    enum Kind: String, Codable, Sendable {
        case scheduled, keepGoing, manual
    }

    /// Why a scheduled ping went out well after its time.
    struct Lateness: Codable, Equatable, Sendable {
        enum Reason: String, Codable, Sendable {
            /// The Mac was asleep when the ping was due.
            case asleep
            /// Tuloy wasn't running then: the Mac was off, or Tuloy had been quit.
            case notRunning
        }

        var due: Date
        var reason: Reason
    }

    /// When it was sent. For a run of the same failure, the latest one.
    var date: Date
    var kind: Kind
    var ok: Bool
    /// When the window resets, if the ping got through.
    var resetsAt: Date?
    /// What went wrong, if it didn't.
    var note: String?
    /// What it cost, in tokens, as counted by Claude Code.
    var tokens: Int?
    /// Set when a scheduled ping went out late, and why.
    var late: Lateness?
    /// For a run of the same failure kept as one line: how many, and when the first was.
    var count: Int?
    var firstDate: Date?
}

/// One day's pings, counted: the squares on History. Kept for a year, after the full list is gone.
struct PingDay: Codable, Equatable, Sendable {
    /// Pings that got through.
    var sent = 0
    /// Pings that didn't.
    var failed = 0
    /// Of those that got through, how many you sent with Ping Now.
    var byYou = 0

    mutating func add(_ ping: PingRecord) {
        let times = ping.count ?? 1
        if ping.ok { sent += times } else { failed += times }
        if ping.ok, ping.kind == .manual { byYou += times }
    }

    /// "2026-10-19": the day a date falls on, in `calendar`. Sorts in date order as text.
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension Date {
    /// Unix time from Claude Code, which may be in seconds or milliseconds.
    init(unixTime value: Double) {
        self.init(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }
}

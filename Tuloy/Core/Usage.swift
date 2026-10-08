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

/// One ping Tuloy sent, for the menu's "Recent Pings" list.
struct PingRecord: Codable, Equatable, Sendable {
    /// Why it was sent: on schedule, by keep going, or by you with "Ping Now".
    enum Kind: String, Codable, Sendable {
        case scheduled, keepGoing, manual
    }

    var date: Date
    var kind: Kind
    var ok: Bool
    /// When the window resets, if the ping got through.
    var resetsAt: Date?
    /// What went wrong, if it didn't.
    var note: String?
    /// What it cost, in tokens, as counted by Claude Code.
    var tokens: Int?
}

extension Date {
    /// Unix time from Claude Code, which may be in seconds or milliseconds.
    init(unixTime value: Double) {
        self.init(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }
}

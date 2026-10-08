import Foundation

/// Decides what Tuloy should do right now.
///
/// No clock, no network: just facts in and a decision out, so every case
/// (asleep at ping time, a window already open, a failed ping) can be tested.
struct Planner: Sendable {
    var schedule: Schedule
    /// The next scheduled ping, the one that sets up your fresh window.
    var nextPingAt: Date?
    /// When the window Tuloy knows about resets.
    var windowResetsAt: Date?
    /// Don't ping before this: set after a failed ping, or while your weekly limit is used up.
    var holdUntil: Date?
    var isPaused = false

    enum Decision: Equatable, Sendable {
        /// Nothing to do yet.
        case wait
        /// Send a ping now.
        case ping(PingRecord.Kind)
        /// The scheduled ping was missed by too much to help. Plan the next one.
        case skip
    }

    /// How long after a window resets before pinging again, so the ping can't land in the old window.
    static let grace: TimeInterval = 60

    func decide(at now: Date, calendar: Calendar = .current) -> Decision {
        guard !isPaused else { return .wait }

        let kind: PingRecord.Kind
        if let due = nextPingAt, now >= due {
            // Missed by more than 5 hours: your fresh window time has passed, so a late ping can't help.
            if now >= due.addingTimeInterval(Schedule.window) { return .skip }
            // On time, or a catch-up after sleep that can still help.
            kind = .scheduled
        } else if schedule.keepsGoing(at: now, calendar: calendar) {
            kind = .keepGoing
        } else {
            return .wait
        }

        // A window is already open, so a ping now would start nothing. Wait for it to end.
        if let windowResetsAt, now < windowResetsAt.addingTimeInterval(Planner.grace) { return .wait }
        if let holdUntil, now < holdUntil { return .wait }
        return .ping(kind)
    }

    /// How long to wait after a failed ping: quick at first (your Mac may have
    /// just woken up), then slower so a lasting problem doesn't mean constant retries.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        let minutes = [1, 2, 5, 15, 30]
        return TimeInterval(minutes[min(max(failures, 1), minutes.count) - 1] * 60)
    }
}

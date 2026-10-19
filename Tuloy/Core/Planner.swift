import Foundation

/// Decides what Tuloy should do right now, and works out what happens next.
///
/// No clock, no network: just facts in and an answer out, so every case
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
    /// The problem only you can fix, if pings are waiting on one.
    var waitingOn: PingError?
    /// Set while your weekly limit is used up. No ping until then: none could start a window.
    var restingUntil: Date?

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

        // Retrying can't fix this one. Wait until you have.
        if waitingOn != nil { return .wait }
        // Your week is used up, so a ping could start nothing.
        if let restingUntil, now < restingUntil { return .wait }
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

    // MARK: - What happens next

    /// When the next ping will go out, and why then.
    ///
    /// It asks `decide` about each moment something could change, in order, and reports the
    /// first one that says "ping". So it can never promise a ping that wouldn't be sent.
    func forecast(at now: Date, calendar: Calendar = .current) -> Forecast {
        if isPaused { return Forecast(date: nil, reason: .paused) }
        if let restingUntil, restingUntil > now { return Forecast(date: restingUntil, reason: .resting) }
        if let waitingOn { return Forecast(date: nil, reason: .waitingOnYou(waitingOn)) }

        var planner = self
        var from = now
        for _ in 0..<4 {
            let windowEnds = planner.windowResetsAt?.addingTimeInterval(Planner.grace)
            let moments = [
                from,
                planner.nextPingAt,
                planner.nextPingAt?.addingTimeInterval(Schedule.window),
                windowEnds,
                planner.holdUntil,
                planner.schedule.nextFresh(after: from, calendar: calendar),
            ]
            .compactMap { $0 }.filter { $0 >= from }.sorted()

            var skippedAt: Date?
            for moment in moments {
                switch planner.decide(at: moment, calendar: calendar) {
                case .wait:
                    continue
                case .ping(let kind):
                    return Forecast(date: moment, reason: planner.reason(for: kind, at: moment, windowEnds: windowEnds))
                case .skip:
                    skippedAt = moment
                }
                if skippedAt != nil { break }
            }

            // The scheduled ping ran out of time. Carry on from there with the one after.
            guard let skippedAt else { break }
            planner.nextPingAt = planner.schedule.nextPing(after: skippedAt, calendar: calendar)
            from = skippedAt
        }
        return Forecast(date: nil, reason: .nothingPlanned)
    }

    /// The thing that made `moment` the moment.
    private func reason(for kind: PingRecord.Kind, at moment: Date, windowEnds: Date?) -> Forecast.Reason {
        if let holdUntil, moment == holdUntil { return .retrying }
        if let windowEnds, moment == windowEnds, let windowResetsAt {
            return kind == .keepGoing ? .keepGoing : .waitingForWindow(until: windowResetsAt)
        }
        if kind == .keepGoing { return .keepGoing }
        let due = nextPingAt ?? moment
        return .scheduled(fresh: due.addingTimeInterval(Schedule.window - Schedule.margin))
    }
}

/// What happens next: when, and why then.
struct Forecast: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// The scheduled ping, 5 hours before the fresh window you asked for.
        case scheduled(fresh: Date)
        /// Keep going: as soon as the open window ends.
        case keepGoing
        /// The scheduled ping is due, but a window is still open.
        case waitingForWindow(until: Date)
        /// Trying again after a ping that didn't get through.
        case retrying
        /// Nothing until you fix something.
        case waitingOnYou(PingError)
        case paused
        /// Your weekly limit is used up.
        case resting
        case nothingPlanned
    }

    /// When the next ping goes out, if Tuloy can say.
    var date: Date?
    var reason: Reason

    /// "Next ping 8:01 PM: when this window ends", for Home and the panel.
    func sentence(now: Date) -> String {
        guard let date else {
            switch reason {
            case .paused: return "No pings while paused"
            case .waitingOnYou(let problem): return "Next ping \(Forecast.waiting(on: problem))"
            default: return "No ping planned: no days chosen"
            }
        }
        if reason != .resting, date.timeIntervalSince(now) < 45 { return "Next ping any moment now" }
        let when = Format.when(date, now: now)
        switch reason {
        case .scheduled(let fresh):
            return "Next ping \(when): 5 hours before your \(fresh.formatted(date: .omitted, time: .shortened)) fresh window"
        case .keepGoing:
            return "Next ping \(when): when this window ends"
        case .waitingForWindow(let until):
            return "Next ping \(when): a window is open until \(until.formatted(date: .omitted, time: .shortened))"
        case .retrying:
            return "Next try \(when): the last one didn't get through"
        case .resting:
            return "Resting until \(when): when your week resets"
        case .waitingOnYou, .paused, .nothingPlanned:
            return "Next ping \(when)"
        }
    }

    /// "Next ping 5:00 AM tomorrow.", for the line that says what just happened.
    func short(now: Date) -> String {
        guard let date else { return sentence(now: now) + "." }
        return reason == .resting ? "Resting until \(Format.when(date, now: now))." : "Next ping \(Format.when(date, now: now))."
    }

    private static func waiting(on problem: PingError) -> String {
        switch problem {
        case .claudeNotFound: return "after Claude Code is installed"
        case .unknownOption: return "after Claude Code is updated"
        case .notOnPlan: return "after you sign in with your Claude account"
        default: return "after you sign in"
        }
    }
}

import Foundation
import Observation

/// The brain: decides when to ping, and what to do with what comes back.
///
/// No screens and no macOS calls. It plugs into four sockets (Sockets.swift), so tests
/// can hand it a pretend clock and a pretend Claude and play out any situation.
/// AppModel adds the windows and the wiring to the real Mac.
@MainActor
@Observable
class Engine {

    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let claude: any ClaudeCode
    @ObservationIgnored let storage: any Storage
    @ObservationIgnored let notices: any Notices
    /// Which calendar "11:00 AM" and "Monday" are read in. Yours, except in tests.
    @ObservationIgnored let calendar: Calendar

    /// False while starting up, so loading saved values doesn't save them straight back.
    @ObservationIgnored private var isReady = false

    // MARK: - Settings (saved automatically)

    /// When you want a fresh window, in minutes after midnight (660 = 11:00 AM).
    var freshMinutes = 11 * 60 {
        didSet { if isReady, freshMinutes != oldValue { storage.set(freshMinutes, for: "freshMinutes"); scheduleChanged() } }
    }

    /// The days you want one (1 = Sunday ... 7 = Saturday).
    var weekdays = Schedule.everyDay {
        didSet { if isReady, weekdays != oldValue { storage.set(weekdays.sorted(), for: "weekdays"); scheduleChanged() } }
    }

    /// Keep going: start a new window each time one ends, until `untilMinutes`.
    var keepGoing = false {
        didSet { if isReady, keepGoing != oldValue { storage.set(keepGoing, for: "keepGoing"); say("Saved. \(forecast.short(now: now))") } }
    }

    var untilMinutes = 18 * 60 {
        didSet { if isReady, untilMinutes != oldValue { storage.set(untilMinutes, for: "untilMinutes"); say("Saved. \(forecast.short(now: now))") } }
    }

    /// Notify when a fresh window opens.
    var notify = true {
        didSet {
            guard isReady else { return }
            storage.set(notify, for: "notify")
            if notify { notices.requestPermission() }
            updateFreshNotification()
        }
    }

    /// Notify at 80% and 95% of a window.
    var warnNearlyOut = true {
        didSet { if isReady { storage.set(warnNearlyOut, for: "warnNearlyOut"); if warnNearlyOut { notices.requestPermission() } } }
    }

    /// Notify at 80% and 95% of the week.
    var warnWeek = true {
        didSet { if isReady { storage.set(warnWeek, for: "warnWeek"); if warnWeek { notices.requestPermission() } } }
    }

    private(set) var isPaused = false {
        didSet { if isReady { storage.set(isPaused, for: "isPaused") } }
    }

    // MARK: - What Tuloy remembers between launches

    /// The next scheduled ping. Saved, so a ping missed while your Mac was
    /// asleep or off still goes out when it wakes.
    private(set) var nextPingAt: Date? {
        didSet { if isReady { storage.set(nextPingAt, for: "nextPingAt") } }
    }

    /// Your current 5-hour window, as last reported by Claude Code.
    private(set) var window: UsageReading? {
        didSet {
            guard isReady else { return }
            storage.saveJSON(window, for: "window")
            if window?.resetsAt != oldValue?.resetsAt { updateFreshNotification() }
        }
    }

    /// Your weekly limit, as last reported by Claude Code.
    private(set) var week: UsageReading? {
        didSet { if isReady { storage.saveJSON(week, for: "week") } }
    }

    /// The latest pings, newest first.
    private(set) var history: [PingRecord] = [] {
        didSet { if isReady { storage.saveJSON(history, for: "history") } }
    }

    /// The windows of the last two weeks, oldest first.
    private(set) var windows: [WindowRecord] = [] {
        didSet { if isReady { storage.saveJSON(windows, for: "windows") } }
    }

    /// Which ping command last worked, and on which Claude Code.
    private(set) var pingMemory: PingMemory? {
        didSet { if isReady { storage.saveJSON(pingMemory, for: "pingMemory") } }
    }

    /// Why today's fresh window isn't when you asked, if it isn't.
    private(set) var planNote: PlanNote? {
        didSet { if isReady { storage.saveJSON(planNote, for: "planNote") } }
    }

    /// The "nearly out" levels already announced, by window or week, so a restart can't repeat them.
    @ObservationIgnored private var announced: [String: Int] = [:] {
        didSet { if isReady { storage.set(announced, for: "announced") } }
    }

    // MARK: - What Tuloy knows only while it runs

    /// Why the last ping failed. Cleared by the next good ping.
    private(set) var problem: PingError?
    /// An extra line for the problem, such as "This started after Claude Code updated".
    private(set) var problemNote: String?
    /// The problem only you can fix, while pings wait on it.
    private(set) var waitingOn: PingError?
    /// Whether Claude Code is installed and signed in. Checked without sending a message.
    private(set) var setup = ClaudeSetup.checking
    /// Where the `claude` command is, once found.
    private(set) var claudePath: String?
    private(set) var isCheckingSetup = false
    /// Set while your weekly limit is used up: pings can't help until it resets.
    private(set) var weekLimitUntil: Date?
    private(set) var isPinging = false
    /// What just happened, for a few seconds.
    private(set) var notice: Notice?
    /// Refreshed every tick so countdowns stay current.
    private(set) var now: Date

    /// Whether the Mac has a connection. A due ping waits for one.
    var isOnline = true {
        didSet {
            // A ping that failed for want of a connection needn't wait out its retry delay.
            if isOnline, !oldValue, problem == .offline { holdUntil = nil }
        }
    }

    /// After a failed ping, when to try again.
    @ObservationIgnored private var holdUntil: Date?
    @ObservationIgnored private var failures = 0
    /// While waiting on you: since when, and when to look again.
    @ObservationIgnored private var waitingSince: Date?
    @ObservationIgnored private var nextCheckAt: Date?
    /// The Claude Code version that was too old, so Tuloy can tell when it changes.
    @ObservationIgnored private var tooOldVersion: String?
    /// The scheduled ping the morning health check has already been run for.
    @ObservationIgnored private var healthCheckedFor: Date?

    init(clock: any Clock, claude: any ClaudeCode, storage: any Storage, notices: any Notices, calendar: Calendar = .current) {
        self.clock = clock
        self.claude = claude
        self.storage = storage
        self.notices = notices
        self.calendar = calendar
        now = clock.now

        freshMinutes = storage.load("freshMinutes", default: 11 * 60)
        weekdays = Set(storage.load("weekdays", default: Array(Schedule.everyDay)))
        keepGoing = storage.load("keepGoing", default: false)
        untilMinutes = storage.load("untilMinutes", default: 18 * 60)
        notify = storage.load("notify", default: true)
        warnNearlyOut = storage.load("warnNearlyOut", default: true)
        warnWeek = storage.load("warnWeek", default: true)
        isPaused = storage.load("isPaused", default: false)
        nextPingAt = storage.value(for: "nextPingAt") as? Date
        window = storage.loadJSON("window")
        week = storage.loadJSON("week")
        history = storage.loadJSON("history") ?? []
        windows = storage.loadJSON("windows") ?? []
        pingMemory = storage.loadJSON("pingMemory")
        planNote = storage.loadJSON("planNote")
        announced = storage.load("announced", default: [:])
        isReady = true

        if nextPingAt == nil { scheduleNextPing() }
    }

    // MARK: - The heartbeat

    /// One pass: refresh the clock, look in on anything that's waiting, send a ping if one is due.
    /// The app calls this every 30 seconds, on waking, and when the internet comes back.
    func tick() async {
        now = clock.now
        await checkWhileWaiting()
        await healthCheckIfDue()

        switch planner.decide(at: now, calendar: calendar) {
        case .wait:
            break
        case .skip:
            scheduleNextPing()
        case .ping(let kind):
            if isOnline { await ping(kind) }
        }
    }

    var planner: Planner {
        Planner(schedule: schedule, nextPingAt: nextPingAt, windowResetsAt: window?.resetsAt, holdUntil: holdUntil,
                isPaused: isPaused, waitingOn: waitingOn, restingUntil: weekLimitUntil)
    }

    /// When the next ping goes out, and why then. Every screen reads this.
    var forecast: Forecast { planner.forecast(at: now, calendar: calendar) }

    // MARK: - Actions

    /// The "Ping Now" button. Works whatever state Tuloy is in.
    func pingNow() async {
        await ping(.manual)
    }

    /// The refresh arrow beside the usage number. A ping only refreshes the number while a
    /// window is open. With none open it would start one, so this refuses and says why.
    func refreshUsage() async {
        now = clock.now
        guard currentWindow != nil else {
            say("No window is open, so there's no usage to refresh. Ping Now would start one.", good: false)
            return
        }
        await ping(.manual)
    }

    func togglePause() {
        isPaused.toggle()
        // On resume, start fresh instead of sending pings missed while paused.
        if isPaused {
            say("Paused. No pings until you resume.")
        } else {
            scheduleChanged()
            say("Resumed. \(forecast.short(now: now))")
        }
    }

    /// Looks at Claude Code's install and sign-in, without sending a message.
    func checkSetup() async {
        guard !isCheckingSetup else { return }
        isCheckingSetup = true
        defer { isCheckingSetup = false }

        claudePath = await claude.locate()
        let result = await claude.checkSetup()
        setup = result
        now = clock.now

        if let trouble = result.problem {
            // Not installed, signed out, or the wrong account: no ping can work. Wait for you.
            wait(on: trouble)
        } else if case .ready = result, let waitingOn {
            if waitingOn == .unknownOption {
                // Too old: only a different Claude Code helps.
                if let version = await claude.version(), version != tooOldVersion { stopWaiting() }
            } else {
                // You've fixed it. Pings can go again, starting with the next tick.
                stopWaiting()
            }
        } else if result == .unknown, waitingOn != nil, waitingOn != .unknownOption {
            // This Claude Code can't say whether it's signed in. Don't wait for ever: try now and then.
            stopWaiting(keepingProblem: true)
            holdUntil = now.addingTimeInterval(30 * 60)
        }

        if waitingOn != nil {
            // Look again every 5 minutes for the first hour, then every half hour.
            let waited = now.timeIntervalSince(waitingSince ?? now)
            nextCheckAt = now.addingTimeInterval(waited < 60 * 60 ? 5 * 60 : 30 * 60)
        }
    }

    /// Takes a reading that didn't come from a ping (Claude Code's status line).
    func take(window newWindow: UsageReading?, week newWeek: UsageReading?) {
        now = clock.now
        if let newWindow, newWindow.resetsAt > now, newWindow.asOf > (window?.asOf ?? .distantPast) {
            let known = currentWindow?.resetsAt == newWindow.resetsAt
            window = newWindow
            noteWindow(newWindow, openedBy: known ? nil : .you)
        }
        if let newWeek, newWeek.resetsAt > now, newWeek.asOf > (week?.asOf ?? .distantPast) {
            week = newWeek
        }
        warnIfNearlyOut()
    }

    /// Puts a line on screen saying what just happened.
    func say(_ text: String, good: Bool = true) {
        notice = Notice(text: text, isGood: good, date: clock.now)
    }

    /// Clears the line, if it's still the one that was showing.
    func dismissNotice(_ shown: Notice?) {
        if notice == shown { notice = nil }
    }

    // MARK: - Pinging

    private func ping(_ kind: PingRecord.Kind) async {
        guard !isPinging else { return }
        isPinging = true
        defer { isPinging = false }

        let due = nextPingAt
        let knownWindow = currentWindow
        let outcome = await claude.ping(remembering: pingMemory)
        now = clock.now

        switch outcome.result {
        case .success(let report):
            pingGotThrough(report, outcome: outcome, kind: kind, due: due, knownWindow: knownWindow)
        case .failure(let error):
            await pingFailed(error, outcome: outcome, kind: kind)
        }
    }

    private func pingGotThrough(_ report: PingReport, outcome: PingOutcome, kind: PingRecord.Kind, due: Date?, knownWindow: UsageReading?) {
        let sentAt = now
        problem = nil
        problemNote = nil
        stopWaiting()
        setup = .ready(plan: setup.plan)
        pingMemory = PingMemory.after(outcome, previous: pingMemory)
        if let week = report.week { self.week = week }

        if report.blockedBy == .week {
            // Your weekly limit is used up, so no window can start. Rest until it resets.
            let resetsAt = report.week?.resetsAt ?? sentAt.addingTimeInterval(60 * 60)
            weekLimitUntil = resetsAt
            holdUntil = resetsAt
            record(PingRecord(date: sentAt, kind: kind, ok: false, note: "Weekly limit used up", tokens: report.tokens))
            say("Your weekly limit is used up. Tuloy rests until \(Format.when(resetsAt, now: now)).", good: false)
            return
        }

        if let window = report.window {
            self.window = window
        } else if currentWindow == nil {
            // Claude Code didn't report the window, so assume this ping opened one.
            window = UsageReading(resetsAt: sentAt.addingTimeInterval(Schedule.window), asOf: sentAt, isEstimate: true)
        }
        weekLimitUntil = nil
        holdUntil = nil
        failures = 0
        let usedUp = report.blockedBy == .window
        record(PingRecord(date: sentAt, kind: kind, ok: true, resetsAt: currentWindow?.resetsAt,
                          note: usedUp ? "Window used up" : nil, tokens: report.tokens))

        guard let window = currentWindow else { return }
        // Was the window already running? Yes if Tuloy knew of it, or if it began well before this ping.
        // (Claude starts windows on 10-minute marks, so "just before" still means this ping opened it.)
        let began = window.resetsAt.addingTimeInterval(-Schedule.window)
        let alreadyOpen = knownWindow?.resetsAt == window.resetsAt || sentAt.timeIntervalSince(began) > 21 * 60
        noteWindow(window, openedBy: alreadyOpen ? .you : .tuloy)

        if kind == .scheduled, let due {
            notePlan(due: due, sentAt: sentAt, window: window, alreadyOpen: alreadyOpen)
        }
        // A ping that opened a window has done the scheduled ping's job, whoever sent it. One that
        // landed in a window already open has started nothing: the scheduled ping stays waiting,
        // and goes out when that window ends.
        if !alreadyOpen, let due, due <= sentAt { scheduleNextPing() }

        let fresh = Format.when(window.resetsAt, now: now)
        if usedUp {
            say("This window is used up. It resets at \(fresh).", good: false)
        } else if alreadyOpen {
            say("Pinged. Your window was already open; it resets at \(fresh).")
        } else if kind == .manual, let next = nextPingAt, next > sentAt, next < window.resetsAt {
            // You started a window by hand that will still be open at the next scheduled ping.
            say("Pinged. Fresh window at \(fresh). Your \(Format.time(next)) ping will wait for this window to end.")
        } else {
            say("Pinged. Fresh window at \(fresh).")
        }
        warnIfNearlyOut()
    }

    private func pingFailed(_ error: PingError, outcome: PingOutcome, kind: PingRecord.Kind) async {
        let failedAt = now
        record(PingRecord(date: failedAt, kind: kind, ok: false, note: error.errorDescription))

        // If Claude Code has changed since the last good ping, that's worth saying.
        var note: String?
        if let worked = pingMemory?.version {
            let version: String?
            if let seen = outcome.version { version = seen } else { version = await claude.version() }
            if let version, version != worked {
                note = "This started after Claude Code updated from \(worked) to \(version)."
            }
        }

        if error.needsYou, error != problem {
            notices.post("problem", title: error.errorDescription ?? "Tuloy needs attention",
                         body: [error.recoverySuggestion, note].compactMap { $0 }.joined(separator: " "))
        }
        problem = error
        problemNote = note
        failures += 1

        switch error.retry {
        case .whenYouFixIt:
            // No retry can work. One free check now and then, until you've fixed it.
            if error == .unknownOption {
                if let seen = outcome.version { tooOldVersion = seen } else { tooOldVersion = await claude.version() }
            }
            wait(on: error)
        case .atNextSchedule:
            // Claude Code says you're signed in, yet refused. Once more at the next scheduled time, not before.
            holdUntil = schedule.nextPing(after: failedAt, calendar: calendar) ?? failedAt.addingTimeInterval(24 * 60 * 60)
        case .soon:
            holdUntil = failedAt.addingTimeInterval(Planner.retryDelay(afterFailures: failures))
        case .soonThenHourly:
            let delay = failures <= 5 ? Planner.retryDelay(afterFailures: failures) : 60 * 60
            holdUntil = failedAt.addingTimeInterval(delay)
        }
        say("That ping didn't get through: \(error.errorDescription ?? "something went wrong")", good: false)
    }

    private func record(_ ping: PingRecord) {
        history = Array(([ping] + history).prefix(20))
    }

    // MARK: - Waiting on you

    private func wait(on trouble: PingError) {
        if waitingOn == nil {
            waitingSince = now
            nextCheckAt = now.addingTimeInterval(5 * 60)
        }
        waitingOn = trouble
        holdUntil = nil
    }

    private func stopWaiting(keepingProblem: Bool = false) {
        guard waitingOn != nil else { return }
        waitingOn = nil
        waitingSince = nil
        nextCheckAt = nil
        tooOldVersion = nil
        holdUntil = nil
        failures = 0
        if !keepingProblem {
            problem = nil
            problemNote = nil
        }
    }

    /// While waiting on you, looks in with the free check: no message is sent.
    private func checkWhileWaiting() async {
        guard waitingOn != nil, let nextCheckAt, now >= nextCheckAt else { return }
        await checkSetup()
    }

    /// An hour before a scheduled ping, makes sure Claude Code is still ready, while there's time to fix it.
    private func healthCheckIfDue() async {
        guard !isPaused, waitingOn == nil, let due = nextPingAt, healthCheckedFor != due,
              now >= due.addingTimeInterval(-60 * 60), now < due
        else { return }

        healthCheckedFor = due
        await checkSetup()
        guard let trouble = setup.problem else { return }

        let fresh = due.addingTimeInterval(Schedule.window - Schedule.margin)
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        notices.post("health", title: trouble.errorDescription ?? "Claude Code isn't ready",
                     body: "Fix it before \(time(due)) to keep your \(time(fresh)) fresh window. Open Tuloy for the steps.")
    }

    // MARK: - Planning

    private func scheduleNextPing() {
        nextPingAt = schedule.nextPing(after: clock.now, calendar: calendar)
    }

    /// You changed when you want fresh windows: plan again from now, with a clean slate.
    private func scheduleChanged() {
        if waitingOn == nil { holdUntil = nil }
        failures = 0
        scheduleNextPing()
        say("Saved. \(forecast.short(now: now))")
    }

    /// Plans again after a change of time zone, unless a ping is already due (that one goes out first).
    func timeZoneChanged() {
        if let due = nextPingAt, due > clock.now { scheduleNextPing() }
    }

    private func updateFreshNotification() {
        let resetsAt = window?.resetsAt
        notices.freshWindow(at: notify && (resetsAt ?? .distantPast) > clock.now ? resetsAt : nil)
    }

    // MARK: - Windows seen, and the plan against the truth

    /// Keeps the list of windows up to date: a new one is added, a known one gets its highest usage raised.
    private func noteWindow(_ reading: UsageReading, openedBy: WindowRecord.Opener?) {
        var list = windows
        if let index = list.firstIndex(where: { abs($0.end.timeIntervalSince(reading.resetsAt)) < 90 }) {
            if let percent = reading.percent { list[index].peak = max(list[index].peak ?? 0, percent) }
        } else {
            list.append(WindowRecord(start: reading.resetsAt.addingTimeInterval(-Schedule.window), end: reading.resetsAt,
                                     openedBy: openedBy ?? .you, peak: reading.percent))
        }
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)
        windows = list.filter { $0.end > twoWeeksAgo }.sorted { $0.start < $1.start }
    }

    /// If the fresh window isn't when you asked, says so, with the reason when Tuloy knows it.
    private func notePlan(due: Date, sentAt: Date, window: UsageReading, alreadyOpen: Bool) {
        let asked = due.addingTimeInterval(Schedule.window - Schedule.margin)
        guard abs(window.resetsAt.timeIntervalSince(asked)) > 10 * 60 else {
            planNote = nil
            return
        }
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        var text = "\(time(window.resetsAt)), not \(time(asked))"
        if alreadyOpen {
            text += ": a window was already running when Tuloy pinged."
        } else if windows.contains(where: { $0.start <= due && due < $0.end && $0.end != window.resetsAt }) {
            text += ": a window was still open at ping time, so Tuloy waited for it to end."
        } else if sentAt.timeIntervalSince(due) > 10 * 60 {
            text += ": the ping went out late, at \(time(sentAt))."
        } else {
            text += "."
        }
        planNote = PlanNote(resetsAt: window.resetsAt, text: text)
    }

    // MARK: - Nearly out

    private static let levels = [80, 95]

    /// Notifies at 80% and 95% of the window and of the week: once each, and only on a current reading.
    private func warnIfNearlyOut() {
        if warnNearlyOut, let window = currentWindow, let level = levelToAnnounce(for: window, named: "window") {
            // Under 10 minutes to the reset, there's nothing useful left to do about it.
            if window.resetsAt.timeIntervalSince(now) >= 10 * 60 {
                notices.post("nearly-out", title: "\(level)% of this window used",
                             body: "Fresh window at \(Format.time(window.resetsAt)), in \(Format.duration(to: window.resetsAt, from: now)).")
            }
        }
        if warnWeek, let week = currentWeek, let level = levelToAnnounce(for: week, named: "week") {
            notices.post("week-nearly-out", title: "Your week is \(level)% used",
                         body: "It resets \(Format.when(week.resetsAt, now: now)).")
        }
    }

    /// The highest level this reading has reached that hasn't been announced yet, marking it announced.
    private func levelToAnnounce(for reading: UsageReading, named name: String) -> Int? {
        guard let percent = reading.percent, now.timeIntervalSince(reading.asOf) <= 10 * 60,
              let level = Engine.levels.last(where: { percent >= $0 })
        else { return nil }

        let key = "\(name)-\(Int(reading.resetsAt.timeIntervalSince1970))"
        guard (announced[key] ?? 0) < level else { return nil }
        // Keep only this window's (or week's) record: the old ones are over.
        announced = announced.filter { !$0.key.hasPrefix(name + "-") }.merging([key: level]) { $1 }
        return level
    }

    // MARK: - What the screens show

    enum Status { case running, paused, resting, problem }

    var status: Status {
        if attention != nil { return .problem }
        if isPaused { return .paused }
        return isResting ? .resting : .running
    }

    /// What needs your attention, if anything: a failed ping, or Claude Code not being ready.
    var attention: PingError? { problem ?? waitingOn ?? setup.problem }

    /// True while your weekly limit is used up.
    var isResting: Bool { weekLimitUntil.map { $0 > now } ?? false }

    /// The current window, if it hasn't reset yet.
    var currentWindow: UsageReading? {
        guard let window, window.resetsAt > now else { return nil }
        return window
    }

    /// Your weekly limit, if it hasn't reset since Tuloy last heard.
    var currentWeek: UsageReading? {
        guard let week, week.resetsAt > now else { return nil }
        return week
    }

    /// When your next fresh window starts: when the open one resets, or the planned time.
    var freshAt: Date? {
        if let currentWindow { return currentWindow.resetsAt }
        guard !isPaused, !isResting, let nextPingAt else { return nil }
        return nextPingAt.addingTimeInterval(Schedule.window - Schedule.margin)
    }

    var usagePercent: Int? { currentWindow?.percent }
    var lastPing: PingRecord? { history.first }

    /// The windows still to come today, as far as Tuloy can tell: the next ping's, then keep going's.
    var windowsToCome: [DateInterval] {
        guard var start = forecast.date else { return [] }
        let endOfDay = calendar.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        var result: [DateInterval] = []
        while start < endOfDay, result.count < 5 {
            let window = DateInterval(start: start, duration: Schedule.window)
            result.append(window)
            let next = window.end.addingTimeInterval(Planner.grace)
            guard schedule.keepsGoing(at: next, calendar: calendar) else { break }
            start = next
        }
        return result
    }

    /// True when the usage on screen is more than 15 minutes old, and should look it.
    var isUsageStale: Bool {
        guard let window = currentWindow, window.percent != nil else { return false }
        return now.timeIntervalSince(window.asOf) > 15 * 60
    }

    /// The reason today's fresh window isn't when you asked, while that window is open.
    var currentPlanNote: String? {
        guard let planNote, planNote.resetsAt == currentWindow?.resetsAt else { return nil }
        return planNote.text
    }

    /// Where things stand, in one line.
    var headline: String {
        if let attention { return attention.errorDescription ?? "Tuloy needs attention" }
        if isPaused { return "Paused" }
        if isResting { return "Weekly limit used up" }
        if let currentWindow {
            return "Fresh window at \(currentWindow.isEstimate ? "about " : "")\(Format.time(currentWindow.resetsAt))"
        }
        guard let freshAt else { return "No fresh window planned" }
        return "Next fresh window at \(Format.time(freshAt))"
    }

    /// The line under the headline: what it means, or what to do.
    var detail: String {
        if let attention {
            return [attention.recoverySuggestion, problemNote].compactMap { $0 }.joined(separator: " ")
        }
        if isPaused { return "Tuloy won't ping until you resume." }
        if isResting, let week = currentWeek { return "It resets \(Format.when(week.resetsAt, now: now)). Tuloy carries on then." }
        if let currentWindow {
            return "Your Claude allowance resets in \(Format.duration(to: currentWindow.resetsAt, from: now))."
        }
        guard let nextPingAt, freshAt != nil else { return "Pick at least one day in Schedule." }
        return "Tuloy pings at \(Format.time(nextPingAt)) to set it up."
    }

    var schedule: Schedule {
        Schedule(freshMinutes: freshMinutes, weekdays: weekdays, keepGoing: keepGoing, untilMinutes: untilMinutes)
    }

    /// The time pickers work with a Date. Tuloy stores minutes.
    var freshTime: Date {
        get { Engine.date(forMinutes: freshMinutes) }
        set { freshMinutes = Engine.minutes(for: newValue) }
    }

    var untilTime: Date {
        get { Engine.date(forMinutes: untilMinutes) }
        set { untilMinutes = Engine.minutes(for: newValue) }
    }

    private static func date(forMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(for date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Made-up data, for demo mode and for drawing screens in tests

    /// Switches to one of the made-up scenes (see Demo.swift).
    func show(_ scene: Demo.Scene) {
        let now = clock.now
        let hours = { (count: Double) in now.addingTimeInterval(count * 3600) }

        self.now = now
        problem = nil
        problemNote = nil
        stopWaiting()
        notice = nil
        planNote = nil
        setup = .ready(plan: "pro")
        claudePath = "~/.local/bin/claude"
        weekLimitUntil = nil
        nextPingAt = schedule.nextPing(after: now)
        week = UsageReading(percent: 41, resetsAt: hours(62), asOf: now)
        history = [
            PingRecord(date: hours(-1.3), kind: .scheduled, ok: true, resetsAt: hours(3.7), tokens: 350),
            PingRecord(date: hours(-6.3), kind: .keepGoing, ok: true, resetsAt: hours(-1.3), tokens: 350),
            PingRecord(date: hours(-11.3), kind: .scheduled, ok: true, resetsAt: hours(-6.3), tokens: 350),
        ]
        windows = [
            WindowRecord(start: hours(-11.3), end: hours(-6.3), openedBy: .tuloy, peak: 88),
            WindowRecord(start: hours(-6.3), end: hours(-1.3), openedBy: .tuloy, peak: 47),
            WindowRecord(start: hours(-1.3), end: hours(3.7), openedBy: .tuloy, peak: 62),
        ]

        switch scene {
        case .running:
            window = UsageReading(percent: 62, resetsAt: hours(3.7), asOf: now.addingTimeInterval(-4 * 60))
        case .almostOut:
            window = UsageReading(percent: 94, resetsAt: hours(0.6), asOf: now.addingTimeInterval(-20 * 60))
        case .waiting:
            window = nil
            windows.removeLast()
            history.removeFirst()
        case .problem:
            window = nil
            windows.removeLast()
            problem = .signedOut
            setup = .signedOut   // so Connection shows the sign-in step
            waitingOn = .signedOut
            history[0] = PingRecord(date: now, kind: .scheduled, ok: false, note: PingError.signedOut.errorDescription)
        case .resting:
            window = nil
            windows.removeLast()
            week = UsageReading(percent: 100, resetsAt: hours(62), asOf: now)
            weekLimitUntil = hours(62)
        }
    }

    /// Demo mode's Sign In: pretend it worked.
    func pretendSignedIn() {
        setup = .ready(plan: "pro")
        problem = nil
        stopWaiting()
        say("Signed in. Send a test ping to finish.")
    }
}

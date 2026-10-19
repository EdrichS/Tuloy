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

    /// Check usage every 5 minutes with Claude Code's own `/usage`. Free: no message is sent.
    var checksUsage = true {
        didSet {
            guard isReady, checksUsage != oldValue else { return }
            storage.set(checksUsage, for: "checksUsage")
            if checksUsage {
                // You switched it back on after Tuloy stopped it: try once more, and watch the cost again.
                usageCheckCost = nil
                nextUsageCheckAt = nil
            }
        }
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

    /// Every ping of the last month, newest first. A run of the same failure is one line.
    private(set) var history: [PingRecord] = [] {
        didSet { if isReady { storage.saveJSON(history, for: "history") } }
    }

    /// How many pings went out each day, for the last year: the squares on History.
    private(set) var pingDays: [String: PingDay] = [:] {
        didSet { if isReady { storage.saveJSON(pingDays, for: "pingDays") } }
    }

    /// Set while your weekly limit is used up: pings can't help until it resets.
    /// Saved, so a restart doesn't spend a ping finding out again.
    private(set) var weekLimitUntil: Date? {
        didSet { if isReady { storage.set(weekLimitUntil, for: "weekLimitUntil") } }
    }

    /// Whether your account has paid extra usage on, as the usage check last said. With it on, a
    /// ping sent while a limit is used up would be paid for, so Tuloy holds such pings back.
    private(set) var extraUsageOn: Bool? {
        didSet { if isReady, extraUsageOn != oldValue { storage.set(extraUsageOn, for: "extraUsageOn") } }
    }

    /// True when Claude Code's own report says it's using an API key, not your Claude plan. Every ping
    /// would then be billed, so none is sent until a later report says otherwise. Saved, so a restart
    /// can't let one through.
    private(set) var apiKeyInUse = false {
        didSet { if isReady { storage.set(apiKeyInUse, for: "apiKeyInUse") } }
    }

    /// Messages you've written for Claude, to be sent later (Messages).
    private(set) var messages: [ScheduledMessage] = [] {
        didSet { if isReady { storage.saveJSON(messages, for: "messages") } }
    }

    /// Each time one of them went out, or should have, newest first. The last month.
    private(set) var messageRuns: [MessageRun] = [] {
        didSet { if isReady { storage.saveJSON(messageRuns, for: "messageRuns") } }
    }

    /// Tokens a usage check once used, if one ever did. Checking stops until you switch it on again.
    private(set) var usageCheckCost: Int? {
        didSet { if isReady { storage.set(usageCheckCost, for: "usageCheckCost") } }
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
    private(set) var isPinging = false
    private(set) var isCheckingUsage = false
    /// The message being sent right now, if one is.
    private(set) var sendingMessage: UUID?
    /// That send, so Stop can end it (and tests can wait for it).
    @ObservationIgnored private(set) var messageTask: Task<Void, Never>?
    /// When a usage check last worked.
    private(set) var usageCheckedAt: Date?
    /// Why the last usage check didn't work, if it didn't.
    private(set) var usageCheckTrouble: String?
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
    @ObservationIgnored private var nextUsageCheckAt: Date?
    /// When Tuloy started, and the last time the Mac slept (a gap in the 30-second ticks).
    /// Together they say why a scheduled ping went out late.
    @ObservationIgnored private let launchedAt: Date
    @ObservationIgnored private var lastTickEndedAt: Date?
    @ObservationIgnored private var lastSleep: DateInterval?

    static let usageCheckInterval: TimeInterval = 5 * 60
    /// How long the full ping list is kept. The squares on History keep a year of daily counts.
    static let historyKept: TimeInterval = 31 * 24 * 60 * 60

    init(clock: any Clock, claude: any ClaudeCode, storage: any Storage, notices: any Notices, calendar: Calendar = .current) {
        self.clock = clock
        self.claude = claude
        self.storage = storage
        self.notices = notices
        self.calendar = calendar
        now = clock.now
        launchedAt = clock.now

        freshMinutes = storage.load("freshMinutes", default: 11 * 60)
        weekdays = Set(storage.load("weekdays", default: Array(Schedule.everyDay)))
        keepGoing = storage.load("keepGoing", default: false)
        untilMinutes = storage.load("untilMinutes", default: 18 * 60)
        notify = storage.load("notify", default: true)
        warnNearlyOut = storage.load("warnNearlyOut", default: true)
        warnWeek = storage.load("warnWeek", default: true)
        isPaused = storage.load("isPaused", default: false)
        checksUsage = storage.load("checksUsage", default: true)
        usageCheckCost = storage.value(for: "usageCheckCost") as? Int
        extraUsageOn = storage.value(for: "extraUsageOn") as? Bool
        apiKeyInUse = storage.load("apiKeyInUse", default: false)
        nextPingAt = storage.value(for: "nextPingAt") as? Date
        window = storage.loadJSON("window")
        week = storage.loadJSON("week")
        weekLimitUntil = (storage.value(for: "weekLimitUntil") as? Date).flatMap { $0 > now ? $0 : nil }
        history = storage.loadJSON("history") ?? []
        pingDays = storage.loadJSON("pingDays") ?? Engine.days(from: history, calendar: calendar)
        windows = storage.loadJSON("windows") ?? []
        messages = storage.loadJSON("messages") ?? []
        messageRuns = (storage.loadJSON("messageRuns") ?? []).map { (run: MessageRun) in
            // One that was still going when Tuloy quit can't be finished now.
            var run = run
            if run.outcome == .running {
                run.outcome = .stopped
                run.text = "Stopped: Tuloy quit while Claude was working on it."
            }
            return run
        }
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
        // Ticks come every 30 seconds while the Mac is awake. A longer gap means it was asleep.
        if let lastTickEndedAt, now.timeIntervalSince(lastTickEndedAt) > 90 {
            lastSleep = DateInterval(start: lastTickEndedAt, end: now)
        }
        defer { lastTickEndedAt = clock.now }

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

        // Started, not waited for: a long piece of work mustn't hold up the next ping.
        sendDueMessage()
        await checkUsageIfDue()
    }

    var planner: Planner {
        Planner(schedule: schedule, nextPingAt: nextPingAt, windowResetsAt: window?.resetsAt, holdUntil: holdUntil,
                isPaused: isPaused, waitingOn: waitingOn, restingUntil: weekLimitUntil)
    }

    /// The free usage check can run: you haven't switched it off, and it has never cost anything.
    var canCheckUsage: Bool { checksUsage && usageCheckCost == nil }

    /// When the next ping goes out, and why then. Every screen reads this.
    var forecast: Forecast { planner.forecast(at: now, calendar: calendar) }

    // MARK: - Actions

    /// The "Ping Now" button. Works whatever state Tuloy is in.
    func pingNow() async {
        await ping(.manual)
    }

    /// The refresh arrow beside the usage number: the free usage check, now.
    ///
    /// If you've switched the check off, or it ever cost tokens, the arrow falls back to a ping,
    /// and only while a window is open: with none open, a ping would start one.
    func refreshUsage() async {
        now = clock.now
        if usageCheckCost == nil {
            // One is already running (the 5-minute check): its answer is moments away.
            guard !isCheckingUsage else { return }
            guard await checkUsage() else {
                say("Couldn't check your usage. \(usageCheckTrouble ?? "Claude Code didn't answer.")", good: false)
                return
            }
            if let window = currentWindow, let percent = window.percent {
                say("\(percent)% of this window used. It resets at \(Format.when(window.resetsAt, now: now)).")
            } else if currentWindow == nil {
                say("No window is open right now.")
            } else {
                say("Usage checked.")
            }
            return
        }
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
        var result = await claude.checkSetup()
        if apiKeyInUse, case .ready = result {
            // The sign-in check says your plan, but Claude Code last reported an API key. Look again,
            // free; until it says otherwise, a ping would be billed.
            if usageCheckCost == nil { await checkUsage() } else { apiKeyInUse = false }
            if apiKeyInUse { result = .notOnPlan }
        }
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

    /// Reads your usage with the free check. Returns false if it didn't work.
    @discardableResult
    func checkUsage() async -> Bool {
        guard !isCheckingUsage, usageCheckCost == nil else { return false }
        isCheckingUsage = true
        defer { isCheckingUsage = false }

        nextUsageCheckAt = clock.now.addingTimeInterval(Engine.usageCheckInterval)
        let outcome = await claude.checkUsage()
        now = clock.now

        if outcome.version != nil { noteAPIKey(outcome.usesAPIKey) }

        guard outcome.wasFree else {
            // Claude Code sent "/usage" to Claude as a message, so the check cost what a ping
            // costs. It must never be a hidden ping: stop, and say so.
            usageCheckCost = outcome.tokens
            checksUsage = false
            usageCheckTrouble = "A usage check used \(outcome.tokens) tokens, so Tuloy stopped checking."
            notices.post("usage-check", title: "Tuloy stopped checking your usage",
                         body: "Claude Code charged \(outcome.tokens) tokens for a check that should be free. Usage now updates only with pings.")
            return false
        }

        switch outcome.result {
        case .success(let report):
            usageCheckTrouble = nil
            usageCheckedAt = now
            // "Last-known" figures could be hours old. The next check will do better.
            if !report.isLastKnown { take(report) }
            return true
        case .failure(let error):
            usageCheckTrouble = error.errorDescription
            return false
        }
    }

    /// Every 5 minutes, while the check is on and Claude Code is ready for it.
    private func checkUsageIfDue() async {
        guard canCheckUsage, isOnline, waitingOn == nil, setup.problem == nil, !isPinging else { return }
        if let nextUsageCheckAt, now < nextUsageCheckAt { return }
        await checkUsage()
    }

    /// Takes what a usage check found.
    private func take(_ report: UsageReport) {
        if let on = report.extraUsageOn { extraUsageOn = on }
        if report.noWindow, let window = currentWindow, now.timeIntervalSince(window.asOf) > 10 * 60 {
            // Claude Code says no window is open, though Tuloy thought one was (an estimate, or
            // limits reset early). Believe Claude Code, so the next ping isn't held back for nothing.
            // A reading under 10 minutes old is left alone: Claude's figures can lag a fresh ping.
            self.window = nil
        }
        take(window: report.window, week: report.week)
    }

    /// Takes a reading that didn't come from a ping: the usage check, or Claude Code's status line.
    func take(window newWindow: UsageReading?, week newWeek: UsageReading?) {
        now = clock.now
        if let newWindow, newWindow.resetsAt > now, newWindow.asOf > (window?.asOf ?? .distantPast) {
            let known = currentWindow.map { Engine.isSameWindow($0.resetsAt, newWindow.resetsAt) } ?? false
            window = newWindow
            noteWindow(newWindow, openedBy: known ? nil : .you)
        }
        if let newWeek, newWeek.resetsAt > now, newWeek.asOf > (week?.asOf ?? .distantPast) {
            week = newWeek
            if let percent = newWeek.percent, percent >= 100 {
                // Used up: no ping can start a window until it resets. Rest till then (for longer, if
                // Tuloy had guessed short), and spend nothing finding out again.
                if (weekLimitUntil ?? .distantPast) < newWeek.resetsAt { weekLimitUntil = newWeek.resetsAt }
            } else if newWeek.percent != nil, let resting = weekLimitUntil, resting > now {
                // The week has room again (it reset early, or a new one began): carry on.
                weekLimitUntil = nil
            }
        }
        warnIfNearlyOut()
    }

    /// True when two reset times are the same window. Sources round differently, by a second or so.
    static func isSameWindow(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 90
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
        now = clock.now
        if setup == .notOnPlan || apiKeyInUse {
            // Claude Code would bill this to an API key instead of using your plan. Nothing is sent.
            if kind == .manual {
                say("Not sent: Claude Code isn't using your Claude plan (it has an API key or another provider), so this ping would be billed. Open Connection to sign in with your Claude account.", good: false)
            }
            return
        }
        if wouldBePaid {
            // A ping can't start a window while a limit is used up, and with extra usage on it would
            // be paid for instead of turned away. Nothing is sent.
            if kind == .manual {
                let limit = (currentWindow?.percent ?? 0) >= 100 ? "window" : "week"
                say("Not sent: your \(limit) is used up and extra usage is on, so this ping would be paid for. It resets \(limitResets.map { Format.when($0, now: now) } ?? "soon").", good: false)
            }
            return
        }
        isPinging = true
        defer { isPinging = false }

        let due = nextPingAt
        let knownWindow = currentWindow
        let late = kind == .scheduled ? lateness(due: due, sentAt: now) : nil
        let outcome = await claude.ping(remembering: pingMemory)
        now = clock.now

        switch outcome.result {
        case .success(let report):
            pingGotThrough(report, outcome: outcome, kind: kind, due: due, late: late, knownWindow: knownWindow)
        case .failure(let error):
            await pingFailed(error, outcome: outcome, kind: kind, late: late)
        }
        if outcome.version != nil { noteAPIKey(outcome.usedAPIKey) }
    }

    /// Takes Claude Code's own word on whether it's using an API key.
    private func noteAPIKey(_ inUse: Bool) {
        guard inUse != apiKeyInUse else { return }
        apiKeyInUse = inUse
        if inUse {
            setup = .notOnPlan
            if waitingOn == nil {
                notices.post("problem", title: PingError.notOnPlan.errorDescription ?? "Claude Code isn't using your Claude plan",
                             body: PingError.notOnPlan.recoverySuggestion ?? "")
            }
            wait(on: .notOnPlan)
        } else if waitingOn == .notOnPlan {
            // Your plan again. Let the sign-in check confirm it at the next tick.
            nextCheckAt = now
        }
    }

    /// True when a ping now would be paid from extra usage: it's on, and a limit is used up.
    var wouldBePaid: Bool {
        guard extraUsageOn == true else { return false }
        return (currentWindow?.percent ?? 0) >= 100 || (currentWeek?.percent ?? 0) >= 100 || isResting
    }

    /// When the used-up limit resets.
    private var limitResets: Date? {
        if let window = currentWindow, (window.percent ?? 0) >= 100 { return window.resetsAt }
        return weekLimitUntil ?? currentWeek?.resetsAt
    }

    /// Why a scheduled ping is going out well after it was due: the Mac was asleep at the time,
    /// or Tuloy wasn't running. Nil if it's on time, or late for another reason (a retry).
    private func lateness(due: Date?, sentAt: Date) -> PingRecord.Lateness? {
        guard let due, sentAt.timeIntervalSince(due) > 2 * 60 else { return nil }
        if let lastSleep, lastSleep.start <= due, lastSleep.end >= due {
            return PingRecord.Lateness(due: due, reason: .asleep)
        }
        if launchedAt > due { return PingRecord.Lateness(due: due, reason: .notRunning) }
        return nil
    }

    private func pingGotThrough(_ report: PingReport, outcome: PingOutcome, kind: PingRecord.Kind, due: Date?,
                                late: PingRecord.Lateness?, knownWindow: UsageReading?) {
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
            record(PingRecord(date: sentAt, kind: kind, ok: false, note: "Weekly limit used up", tokens: report.tokens, late: late))
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
        if report.usedExtraUsage {
            // Claude says this ping was paid from extra usage. It shouldn't happen (Tuloy holds pings
            // back when it knows a limit is used up), but if it does, say so, plainly and at once.
            extraUsageOn = true
            notices.post("extra-usage", title: "A ping was paid from your extra usage",
                         body: "A limit was used up and extra usage is on. Tuloy won't ping again while a limit is used up.")
        }
        record(PingRecord(date: sentAt, kind: kind, ok: true, resetsAt: currentWindow?.resetsAt,
                          note: report.usedExtraUsage ? "Paid from extra usage" : usedUp ? "Window used up" : nil,
                          tokens: report.tokens, late: late))

        guard let window = currentWindow else { return }
        // Was the window already running? Yes if Tuloy knew of it, or if it began well before this ping.
        // (Claude starts windows on 10-minute marks, so "just before" still means this ping opened it.)
        let began = window.resetsAt.addingTimeInterval(-Schedule.window)
        let alreadyOpen = knownWindow.map { Engine.isSameWindow($0.resetsAt, window.resetsAt) } ?? false
            || sentAt.timeIntervalSince(began) > 21 * 60
        noteWindow(window, openedBy: alreadyOpen ? .you : .tuloy)

        if kind == .scheduled, let due {
            notePlan(due: due, sentAt: sentAt, window: window, alreadyOpen: alreadyOpen, late: late)
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

    private func pingFailed(_ error: PingError, outcome: PingOutcome, kind: PingRecord.Kind, late: PingRecord.Lateness?) async {
        let failedAt = now
        record(PingRecord(date: failedAt, kind: kind, ok: false, note: error.errorDescription, late: late))

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

    /// Day counts worked out from a ping list. For the first run after updating from a version without them.
    private static func days(from history: [PingRecord], calendar: Calendar) -> [String: PingDay] {
        var days: [String: PingDay] = [:]
        for ping in history {
            days[PingDay.key(for: ping.date, calendar: calendar), default: PingDay()].add(ping)
        }
        return days
    }

    /// Adds a ping to History, and to its day's count.
    private func record(_ ping: PingRecord) {
        var list = history
        if !ping.ok, let latest = list.first, !latest.ok, latest.kind == ping.kind, latest.note == ping.note {
            // The same failure again: one line that counts them, not a screenful of copies.
            var folded = ping
            folded.count = (latest.count ?? 1) + 1
            folded.firstDate = latest.firstDate ?? latest.date
            folded.late = latest.late ?? ping.late
            list[0] = folded
        } else {
            list.insert(ping, at: 0)
        }
        let monthAgo = ping.date.addingTimeInterval(-Engine.historyKept)
        history = Array(list.prefix { $0.date > monthAgo }.prefix(2000))

        let day = PingDay.key(for: ping.date, calendar: calendar)
        var days = pingDays
        days[day, default: PingDay()].add(ping)
        let yearAgo = PingDay.key(for: ping.date.addingTimeInterval(-400 * 24 * 60 * 60), calendar: calendar)
        pingDays = days.filter { $0.key >= yearAgo }
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
            let start = reading.resetsAt.addingTimeInterval(-Schedule.window)
            // One window can't start inside another. If an earlier one runs past this start, Claude's
            // newer word wins: that one ended here (limits reset early, or the earlier reading was off).
            for index in list.indices where list[index].start < start && list[index].end > start {
                list[index].end = start
            }
            list.append(WindowRecord(start: start, end: reading.resetsAt, openedBy: openedBy ?? .you, peak: reading.percent))
        }
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)
        windows = list.filter { $0.end > twoWeeksAgo }.sorted { $0.start < $1.start }
    }

    /// If the fresh window isn't when you asked, says so, with the reason when Tuloy knows it.
    private func notePlan(due: Date, sentAt: Date, window: UsageReading, alreadyOpen: Bool, late: PingRecord.Lateness?) {
        let asked = due.addingTimeInterval(Schedule.window - Schedule.margin)
        let off = window.resetsAt.timeIntervalSince(asked)
        guard abs(off) > 60 else {
            planNote = nil
            return
        }
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        var text = "\(time(window.resetsAt)), not \(time(asked))"
        if alreadyOpen {
            text += ": a window was already running when Tuloy pinged."
        } else if windows.contains(where: { $0.start <= due && due < $0.end && !Engine.isSameWindow($0.end, window.resetsAt) }) {
            text += ": a window was still open at ping time, so Tuloy waited for it to end."
        } else if let late {
            let why = late.reason == .asleep ? "your Mac was asleep" : "Tuloy wasn't running"
            text += ": \(why) at \(time(late.due)), so the ping went out at \(time(sentAt))."
        } else if sentAt.timeIntervalSince(due) > 10 * 60 {
            text += ": the ping went out late, at \(time(sentAt))."
        } else if off < 0, off > -10 * 60 {
            // Claude counts a window from the 10-minute mark before your first message.
            let start = window.resetsAt.addingTimeInterval(-Schedule.window)
            text += ": Claude starts each window on the 10-minute mark, so a \(time(sentAt)) ping counts from \(time(start)). "
                + "A fresh time on the 10s (like \(time(window.resetsAt))) comes out exact."
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
        guard let planNote, let currentWindow, Engine.isSameWindow(planNote.resetsAt, currentWindow.resetsAt) else { return nil }
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

    // MARK: - Your scheduled messages

    /// How late a message may go out after the Mac slept, before it counts as missed.
    static let messageLateLimit: TimeInterval = 3 * 60 * 60

    /// Adds a message, or saves the changes to one, and works out when it goes.
    func save(_ message: ScheduledMessage) {
        var message = message
        now = clock.now
        message.nextRun = message.isOn ? firstRun(of: message) : nil
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        if message.notifies { notices.requestPermission() }
        if let next = message.nextRun {
            say("Saved. \(message.name) goes \(Format.when(next, now: now)).")
        } else if message.isOn {
            say("Saved. \(message.name) goes when your next fresh window is planned.")
        } else {
            say("Saved. \(message.name) is switched off.")
        }
    }

    func deleteMessage(_ id: UUID) {
        if sendingMessage == id { stopSending() }
        messages.removeAll { $0.id == id }
    }

    /// Switches a message on (working out when it goes next) or off.
    func setMessage(_ id: UUID, isOn: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        now = clock.now
        var message = messages[index]
        message.isOn = isOn
        message.nextRun = isOn ? firstRun(of: message) : nil
        messages[index] = message
    }

    /// Sends a message now, whatever its schedule says. Its schedule carries on as before.
    func sendNow(_ id: UUID) {
        guard sendingMessage == nil, let message = messages.first(where: { $0.id == id }) else { return }
        now = clock.now
        start(message, late: nil, byHand: true)
    }

    /// Stops the message being sent. Claude Code is asked to stop; what it had done stays done.
    func stopSending() {
        messageTask?.cancel()
    }

    /// The next of your messages to go out, if any is planned.
    var nextMessage: ScheduledMessage? {
        messages.filter { $0.isOn && $0.nextRun != nil }.min { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
    }

    /// When a message would first go out if saved now.
    func firstRun(of message: ScheduledMessage) -> Date? {
        switch message.when {
        case .once(let moment):
            return max(moment, now)
        case .daily:
            return message.nextTime(after: now, calendar: calendar)
        case .nextFreshWindow:
            return freshWindowTarget
        }
    }

    /// The moment the next fresh window opens: when the open one resets, or Tuloy's planned one.
    /// A minute after, so the message lands in the new window, not the old.
    var freshWindowTarget: Date? {
        (currentWindow?.resetsAt ?? freshAt).map { $0.addingTimeInterval(Planner.grace) }
    }

    /// Starts the message that's due, if one is. Never more than one at a time.
    private func sendDueMessage() {
        // A fresh-window message follows the window that's open: if you open one, it moves to that one's
        // end. One saved before any fresh window was planned takes the first one that is.
        for index in messages.indices where messages[index].isOn {
            guard case .nextFreshWindow = messages[index].when else { continue }
            let next = messages[index].nextRun
            if let window = currentWindow, next.map({ now < $0 }) ?? true {
                let target = window.resetsAt.addingTimeInterval(Planner.grace)
                if next.map({ !Engine.isSameWindow(target, $0) }) ?? true { messages[index].nextRun = target }
            } else if next == nil, let target = freshWindowTarget {
                messages[index].nextRun = target
            }
        }

        guard sendingMessage == nil, isOnline else { return }
        let due = messages.filter { $0.isOn && ($0.nextRun ?? .distantFuture) <= now }
        guard let message = due.min(by: { ($0.nextRun ?? now) < ($1.nextRun ?? now) }), let time = message.nextRun else { return }

        let late = lateness(due: time, sentAt: now)
        if now.timeIntervalSince(time) > Engine.messageLateLimit || (late != nil && !message.sendsLate) {
            // Too late to be what you asked for. Say so, and move on to its next time.
            let why = late?.reason == .notRunning ? "Tuloy wasn't running" : "your Mac was asleep"
            recordRun(MessageRun(messageID: message.id, title: message.name, started: now, finished: now, outcome: .notSent,
                                 text: "Missed: \(why) at \(Format.time(time)). Not sent late" +
                                    (message.sendsLate ? ", as it would have been over 3 hours late." : ", as you asked."),
                                 folder: message.folder, late: late))
            advance(message.id)
            return
        }
        advance(message.id)
        start(message, late: late, byHand: false)
    }

    /// After a message has gone (or been missed): a one-off switches off, a daily one moves on.
    private func advance(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].repeats {
            messages[index].nextRun = messages[index].nextTime(after: now, calendar: calendar)
        } else {
            messages[index].isOn = false
            messages[index].nextRun = nil
        }
    }

    private func start(_ message: ScheduledMessage, late: PingRecord.Lateness?, byHand: Bool) {
        sendingMessage = message.id
        messageTask = Task { await send(message, late: late, byHand: byHand) }
    }

    /// Why a message mustn't go right now, if it mustn't: it would be paid for, or can't start anything.
    private var reasonNotToSend: String? {
        if setup == .notOnPlan || apiKeyInUse {
            return "Not sent: Claude Code isn't using your Claude plan (it has an API key or another provider), so this would be billed."
        }
        if wouldBePaid {
            return "Not sent: a limit is used up and extra usage is on, so this would be paid for."
        }
        if isResting, let until = weekLimitUntil {
            return "Not sent: your weekly limit is used up until \(Format.when(until, now: now))."
        }
        return nil
    }

    private func send(_ message: ScheduledMessage, late: PingRecord.Lateness?, byHand: Bool) async {
        defer {
            sendingMessage = nil
            messageTask = nil
        }
        let startedAt = clock.now
        var run = MessageRun(messageID: message.id, title: message.name, started: startedAt, outcome: .running, text: "",
                             folder: message.folder, late: late)
        if let reason = reasonNotToSend {
            run.finished = startedAt
            run.outcome = .notSent
            run.text = reason
            recordRun(run)
            if byHand { say(reason, good: false) }
            return
        }
        recordRun(run)
        if byHand { say("Sending \(message.name)…") }

        let knownWindow = currentWindow
        let outcome = await claude.send(message)
        let wasStopped = Task.isCancelled
        now = clock.now

        run.finished = now
        run.tokens = outcome.report.tokens
        run.model = outcome.model
        run.refused = outcome.refused
        if message.keepsConversation { run.sessionID = outcome.sessionID }
        switch outcome.result {
        case .success(let reply):
            run.outcome = .done
            run.text = String(reply.prefix(100_000))
        case .failure(let error):
            if wasStopped {
                run.outcome = .stopped
                run.text = "Stopped by you."
            } else if error == .timedOut {
                run.outcome = .stopped
                run.text = "Stopped: it ran past its \(message.minutesAllowed) minutes."
            } else {
                run.outcome = .failed
                run.text = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
            }
        }
        if outcome.version != nil { noteAPIKey(outcome.usedAPIKey) }
        (run.windowResets, run.openedWindow) = takeMessageReport(outcome.report, sentAt: startedAt, knownWindow: knownWindow)
        recordRun(run)

        let reply = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.notifies {
            notices.post("message-\(message.id.uuidString)",
                         title: run.outcome == .done ? "\(message.name) is done" : "\(message.name) didn't finish",
                         body: reply.isEmpty ? "Claude finished without a written reply." : String(reply.prefix(240)))
        }
        say(run.outcome == .done ? "\(message.name) is done. The reply is in Messages." : "\(message.name): \(run.text)",
            good: run.outcome == .done)
    }

    /// Adds a run to the list, or updates it, keeping a month.
    private func recordRun(_ run: MessageRun) {
        var list = messageRuns
        if let index = list.firstIndex(where: { $0.id == run.id }) { list[index] = run } else { list.insert(run, at: 0) }
        let monthAgo = clock.now.addingTimeInterval(-Engine.historyKept)
        messageRuns = Array(list.filter { $0.started > monthAgo }.prefix(300))
    }

    /// What a message's output said about your limits, taken like a ping's. Returns when the window it
    /// landed in resets, and whether the message opened it.
    private func takeMessageReport(_ report: PingReport, sentAt: Date, knownWindow: UsageReading?) -> (Date?, Bool) {
        if let week = report.week { take(window: nil, week: week) }
        if report.blockedBy == .week {
            weekLimitUntil = report.week?.resetsAt ?? now.addingTimeInterval(60 * 60)
        }
        guard let reading = report.window else { return (nil, false) }

        let began = reading.resetsAt.addingTimeInterval(-Schedule.window)
        let alreadyOpen = knownWindow.map { Engine.isSameWindow($0.resetsAt, reading.resetsAt) } ?? false
            || sentAt.timeIntervalSince(began) > 21 * 60
        if reading.asOf > (window?.asOf ?? .distantPast) { window = reading }
        noteWindow(reading, openedBy: alreadyOpen ? .you : .tuloy)
        // A message that opened a window right at the scheduled ping's time has done that ping's job.
        // (Planned from after its time, since the message may have gone a few minutes before it.)
        if !alreadyOpen, let due = nextPingAt, abs(sentAt.timeIntervalSince(due)) <= 10 * 60 {
            nextPingAt = schedule.nextPing(after: max(now, due), calendar: calendar)
        }
        warnIfNearlyOut()
        return (reading.resetsAt, !alreadyOpen)
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
        // Earlier days: a few months of made-up pings, the same every time.
        var days: [String: PingDay] = [:]
        var older: [PingRecord] = []
        for back in 1...150 {
            let seed = (back * 37 + 11) % 13
            let day = PingDay(sent: seed < 2 ? 0 : seed < 7 ? 1 : seed < 11 ? 2 : 3, failed: seed == 1 ? 2 : 0, byYou: seed == 12 ? 1 : 0)
            let date = hours(-24 * Double(back))
            days[PingDay.key(for: date, calendar: calendar)] = day
            guard back <= 30 else { continue }
            let six = calendar.date(bySettingHour: 6, minute: 0, second: 15, of: date) ?? date
            if day.failed > 0 {
                older.append(PingRecord(date: six.addingTimeInterval(180), kind: .scheduled, ok: false,
                                        note: PingError.offline.errorDescription, count: day.failed, firstDate: six))
            }
            for index in 0..<day.sent {
                let sentAt = six.addingTimeInterval(Double(index) * Schedule.window + 60)
                let late = back == 4 && index == 0 ? PingRecord.Lateness(due: six, reason: .asleep) : nil
                older.append(PingRecord(date: late == nil ? sentAt : sentAt.addingTimeInterval(72 * 60),
                                        kind: day.byYou > 0 && index == day.sent - 1 ? .manual : index == 0 ? .scheduled : .keepGoing,
                                        ok: true, resetsAt: sentAt.addingTimeInterval(Schedule.window), tokens: 350, late: late))
            }
        }
        older.sort { $0.date > $1.date }
        history += older
        for ping in history.prefix(3) { days[PingDay.key(for: ping.date, calendar: calendar), default: PingDay()].add(ping) }
        pingDays = days

        // Two made-up messages, and what came back.
        var standup = ScheduledMessage()
        standup.title = "Morning summary"
        standup.prompt = "Read the changes in this project since yesterday and list what's left to do, most important first."
        standup.when = .daily(minutes: 8 * 60 + 30, weekdays: [2, 3, 4, 5, 6])
        standup.model = "sonnet"
        standup.effort = "medium"
        standup.folder = "~/Projects/tuloy"
        standup.access = .read
        standup.nextRun = standup.nextTime(after: now, calendar: calendar)
        var refactor = ScheduledMessage()
        refactor.title = "Finish the refactor"
        refactor.prompt = "Carry on splitting Engine.swift into smaller files. Run the tests when you're done."
        refactor.when = .nextFreshWindow
        refactor.model = "opus"
        refactor.effort = "high"
        refactor.folder = "~/Projects/tuloy"
        refactor.access = .edit
        refactor.nextRun = hours(3.7).addingTimeInterval(Planner.grace)
        messages = [standup, refactor]
        messageRuns = [
            MessageRun(messageID: standup.id, title: standup.name, started: hours(-17.5), finished: hours(-17.45), outcome: .done,
                       text: "Three changes since yesterday:\n1. History screen added.\n2. Usage now checked every 5 minutes.\n3. The glyph replaces the stock symbols.\n\nLeft to do: the sounds, the logo, and screenshots for the README.",
                       tokens: 18_420, sessionID: "demo-session", folder: standup.folder, model: "claude-sonnet",
                       windowResets: hours(-13.2)),
            MessageRun(messageID: refactor.id, title: refactor.name, started: hours(-40), finished: hours(-39.9), outcome: .failed,
                       text: "I couldn't run the tests: running commands isn't allowed for this message.",
                       tokens: 9_870, folder: refactor.folder, model: "claude-opus", refused: ["Bash"]),
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

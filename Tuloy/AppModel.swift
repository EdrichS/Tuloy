import AppKit
import Network
import Observation

/// Everything Tuloy knows and does, in one place.
///
/// The loop: every 30 seconds, check the clock. When a ping is due, send it
/// through Claude Code and keep what it reports about your limits.
@MainActor
@Observable
final class AppModel {
    /// The one model, shared by the menu bar, every window, and the app delegate.
    static let shared = AppModel()

    // MARK: - Settings (saved automatically)

    /// When you want a fresh window, in minutes after midnight (660 = 11:00 AM).
    var freshMinutes: Int = saved("freshMinutes", default: 11 * 60) {
        didSet { if freshMinutes != oldValue { save(freshMinutes, "freshMinutes"); scheduleChanged() } }
    }

    /// The days you want one (1 = Sunday ... 7 = Saturday).
    var weekdays: Set<Int> = Set(saved("weekdays", default: Array(Schedule.everyDay))) {
        didSet { if weekdays != oldValue { save(weekdays.sorted(), "weekdays"); scheduleChanged() } }
    }

    /// Keep going: start a new window each time one ends, until `untilMinutes`.
    var keepGoing: Bool = saved("keepGoing", default: false) {
        didSet { save(keepGoing, "keepGoing") }
    }

    var untilMinutes: Int = saved("untilMinutes", default: 18 * 60) {
        didSet { save(untilMinutes, "untilMinutes") }
    }

    var displayMode: DisplayMode = DisplayMode(rawValue: saved("displayMode", default: "")) ?? .classic {
        didSet { save(displayMode.rawValue, "displayMode") }
    }

    var notify: Bool = saved("notify", default: true) {
        didSet {
            save(notify, "notify")
            if notify { Notifier.requestPermission() }
            updateNotification()
        }
    }

    /// Show the Tuloy window when you open the app (but not when it starts by itself at login).
    var openAtLaunch: Bool = saved("openAtLaunch", default: true) {
        didSet { save(openAtLaunch, "openAtLaunch") }
    }

    /// Show the small always-on-top window whenever Tuloy starts.
    var miniAtLaunch: Bool = saved("miniAtLaunch", default: false) {
        didSet { save(miniAtLaunch, "miniAtLaunch") }
    }

    private(set) var isPaused: Bool = saved("isPaused", default: false) {
        didSet { save(isPaused, "isPaused") }
    }

    // MARK: - State

    /// The next scheduled ping. Saved, so a ping missed while your Mac was
    /// asleep or off still goes out when it wakes.
    private(set) var nextPingAt: Date? = store.object(forKey: "nextPingAt") as? Date {
        didSet { save(nextPingAt, "nextPingAt") }
    }

    /// Your current 5-hour window, as last reported by Claude Code.
    private(set) var window: UsageReading? = savedJSON("window") {
        didSet {
            saveJSON(window, "window")
            if window?.resetsAt != oldValue?.resetsAt { updateNotification() }
        }
    }

    /// Your weekly limit, as last reported by Claude Code.
    private(set) var week: UsageReading? = savedJSON("week") {
        didSet { saveJSON(week, "week") }
    }

    /// The latest pings, newest first.
    private(set) var history: [PingRecord] = savedJSON("history") ?? [] {
        didSet { saveJSON(history, "history") }
    }

    /// Why the last ping failed. Cleared by the next good ping.
    private(set) var problem: PingError?
    /// Whether Claude Code is installed and signed in. Checked without sending a message.
    private(set) var setup = ClaudeSetup.checking
    /// Where the `claude` command is, once found.
    private(set) var claudePath: String?
    private(set) var isCheckingSetup = false
    /// Set while your weekly limit is used up: pings can't help until it resets.
    private(set) var weekLimitUntil: Date?
    /// When Claude Code's status line last saved live usage, if it's connected.
    private(set) var liveUsageAt: Date?
    /// True when Claude Code's status line runs Tuloy's script (Connection, step 4).
    private(set) var isLiveUsageConnected = false
    /// Why connecting or disconnecting didn't work, if it didn't.
    private(set) var liveUsageError: String?
    private(set) var isPinging = false
    private(set) var isOnline = true
    /// Refreshed every tick so countdowns stay current.
    private(set) var now = Date()

    /// True the first time Tuloy runs, so it can open the welcome window.
    var isFirstLaunch: Bool = !saved("hasLaunched", default: false) {
        didSet { save(!isFirstLaunch, "hasLaunched") }
    }

    // MARK: - Windows

    /// Windows waiting to be opened. The menu bar item opens them, since only a view can.
    var windowRequests: [WindowID] = []
    /// The screen showing in the main window.
    var mainTab = MainTab.home

    /// After a failed ping, when to try again.
    @ObservationIgnored private var holdUntil: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let network = NWPathMonitor()

    init() {
        if Demo.isOn {
            // Made-up data only: no pings, no Claude Code, none of your settings.
            setup = .ready(plan: "pro")
            claudePath = "~/.local/bin/claude"
            show(.running)
            startClock()
            return
        }

        try? FileManager.default.createDirectory(at: Paths.tuloy, withIntermediateDirectories: true)
        // Keeps the 30-second clock on time while Tuloy sits in the menu bar. Your Mac can still sleep.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Tuloy ping schedule")
        if notify { Notifier.requestPermission() }
        if nextPingAt == nil { scheduleNextPing() }
        startClock()
        tickOnWake()
        tickWhenOnline()
        replanWhenTimeZoneChanges()
        refreshLiveUsage()
        Task { await checkSetup() }
    }

    // MARK: - The loop

    /// Checks the clock every 30 seconds instead of setting one long timer,
    /// so sleep and shutdown can't throw the schedule off.
    private func startClock() {
        Task {
            while true {
                await tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Checks soon after your Mac wakes, so a missed ping goes out quickly.
    private func tickOnWake() {
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task {
                try? await Task.sleep(for: .seconds(5))   // give Wi-Fi a moment
                await self?.tick()
            }
        }
    }

    /// Follows your connection, so a due ping waits for the internet instead of failing.
    private func tickWhenOnline() {
        network.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                if online { await self.tick() }
            }
        }
        network.start(queue: .global(qos: .utility))
    }

    /// Keeps "11:00 AM" meaning 11:00 AM where you are, when you travel.
    private func replanWhenTimeZoneChanges() {
        _ = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // A ping that's already due still goes out first. It replans when it's done.
                guard let self, let due = self.nextPingAt, due > Date() else { return }
                self.scheduleNextPing()
            }
        }
    }

    /// The heartbeat: refresh the clock, pick up live usage, send a ping if one is due.
    func tick() async {
        now = Date()
        guard !Demo.isOn else { return }
        readLiveUsage()

        switch planner.decide(at: now) {
        case .wait:
            break
        case .skip:
            scheduleNextPing()
        case .ping(let kind):
            if isOnline { await ping(kind) }
        }
    }

    private var planner: Planner {
        Planner(schedule: schedule, nextPingAt: nextPingAt, windowResetsAt: window?.resetsAt,
                holdUntil: holdUntil, isPaused: isPaused)
    }

    /// Picks up usage saved by Claude Code's status line, if you've connected it (see README).
    private func readLiveUsage() {
        guard let modified = StatusLineFile.modified, modified > (liveUsageAt ?? .distantPast),
              let live = StatusLineFile.read(asOf: modified)
        else { return }

        liveUsageAt = modified
        if let reading = live.window, reading.resetsAt > now, reading.asOf > (window?.asOf ?? .distantPast) {
            window = reading
        }
        if let reading = live.week, reading.resetsAt > now, reading.asOf > (week?.asOf ?? .distantPast) {
            week = reading
        }
    }

    // MARK: - Actions

    /// The "Ping Now" button.
    func pingNow() async {
        await ping(.manual)
    }

    func togglePause() {
        isPaused.toggle()
        // On resume, start fresh instead of sending pings missed while paused.
        if !isPaused { scheduleChanged() }
    }

    /// Looks at Claude Code's install and sign-in, without sending a message.
    func checkSetup() async {
        guard !Demo.isOn, !isCheckingSetup else { return }
        isCheckingSetup = true
        defer { isCheckingSetup = false }

        claudePath = await ClaudeCLI.locate().map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }
        setup = await ClaudeCLI.checkSetup()

        // You fixed it (say, by signing in): drop the old complaint and let pings try again right away.
        if case .ready = setup, let problem, [.claudeNotFound, .signedOut, .notOnPlan].contains(problem) {
            self.problem = nil
            holdUntil = nil
            failures = 0
        }
    }

    /// Opens Terminal on Claude Code's own sign-in. You sign in there, in your browser;
    /// Tuloy never sees your login. Returns false if Terminal couldn't be opened.
    @discardableResult
    func signInWithTerminal() async -> Bool {
        if Demo.isOn {
            // Pretend you signed in.
            setup = .ready(plan: "pro")
            problem = nil
            return true
        }
        guard let claude = await ClaudeCLI.locate() else { return false }
        let script = ClaudeCLI.signInScript(for: claude)
        let file = Paths.tuloy.appending(path: "Sign in to Claude Code.command")
        do {
            try FileManager.default.createDirectory(at: Paths.tuloy, withIntermediateDirectories: true)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        } catch {
            return false
        }
        return NSWorkspace.shared.open(file)
    }

    // MARK: - Windows

    /// Asks for a window to be opened and brought to the front.
    func open(_ window: WindowID, tab: MainTab? = nil) {
        if let tab { mainTab = tab }
        windowRequests.append(window)
    }

    /// Decides what to show when Tuloy starts: the welcome the first time, the main
    /// window when you opened the app yourself, nothing when it started by itself at login.
    func didLaunch(atLogin: Bool) {
        if Demo.isOn {
            open(Demo.showsSetup ? .setup : .main)
            if !Demo.showsSetup { open(.mini) }
            return
        }
        if isFirstLaunch {
            isFirstLaunch = false
            open(.setup)
        } else if openAtLaunch, !atLogin {
            open(.main)
        }
        if miniAtLaunch { open(.mini) }
    }

    /// Connects or disconnects Claude Code's status line, the source of live usage.
    func setLiveUsage(connected: Bool) {
        guard !Demo.isOn else {
            isLiveUsageConnected = connected
            return
        }
        do {
            if connected { try StatusLineLink().connect() } else { try StatusLineLink().disconnect() }
            liveUsageError = nil
        } catch {
            liveUsageError = error.localizedDescription
        }
        refreshLiveUsage()
    }

    /// Looks again at whether the status line is connected. You might have changed it yourself.
    func refreshLiveUsage() {
        guard !Demo.isOn else { return }
        isLiveUsageConnected = StatusLineLink().isConnected
        if StatusLineFile.modified == nil { liveUsageAt = nil }
    }

    private func ping(_ kind: PingRecord.Kind) async {
        guard !isPinging else { return }
        isPinging = true
        defer { isPinging = false }

        do {
            let report = Demo.isOn ? await Demo.ping() : try await ClaudeCLI.ping()
            let sentAt = Date()
            now = sentAt
            problem = nil
            setup = .ready(plan: setup.plan)
            if let week = report.week { self.week = week }

            if report.blockedBy == .week {
                // Your weekly limit is used up, so no window can start. Rest until it resets.
                let resetsAt = report.week?.resetsAt ?? sentAt.addingTimeInterval(60 * 60)
                weekLimitUntil = resetsAt
                holdUntil = resetsAt
                record(PingRecord(date: sentAt, kind: kind, ok: false, note: "Weekly limit used up", tokens: report.tokens))
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
            record(PingRecord(date: sentAt, kind: kind, ok: true, resetsAt: currentWindow?.resetsAt, tokens: report.tokens))
            // Any ping that got through covers a scheduled one that was waiting.
            if let due = nextPingAt, due <= sentAt { scheduleNextPing() }
        } catch {
            let error = error as? PingError ?? .failed(error.localizedDescription)
            now = Date()
            record(PingRecord(date: now, kind: kind, ok: false, note: error.errorDescription))
            if notify, error.needsYou, error != problem { Notifier.problem(error) }
            problem = error
            failures += 1
            holdUntil = now.addingTimeInterval(Planner.retryDelay(afterFailures: failures))
        }
    }

    private func record(_ ping: PingRecord) {
        history = Array(([ping] + history).prefix(20))
    }

    private func scheduleNextPing() {
        nextPingAt = schedule.nextPing(after: Date())
    }

    /// You changed when you want fresh windows: plan again from now, with a clean slate.
    private func scheduleChanged() {
        holdUntil = nil
        failures = 0
        scheduleNextPing()
    }

    private func updateNotification() {
        if notify, let resetsAt = window?.resetsAt, resetsAt > Date() {
            Notifier.freshWindow(at: resetsAt)
        } else {
            Notifier.cancelFreshWindow()
        }
    }

    // MARK: - Demo mode

    /// Switches to one of the made-up scenes (see Demo.swift).
    func show(_ scene: Demo.Scene) {
        let now = Date()
        let hours = { (count: Double) in now.addingTimeInterval(count * 3600) }

        self.now = now
        problem = nil
        setup = .ready(plan: "pro")
        weekLimitUntil = nil
        nextPingAt = schedule.nextPing(after: now)
        week = UsageReading(percent: 41, resetsAt: hours(62), asOf: now)
        history = [
            PingRecord(date: hours(-1.3), kind: .scheduled, ok: true, resetsAt: hours(3.7)),
            PingRecord(date: hours(-20.3), kind: .keepGoing, ok: true, resetsAt: hours(-15.3)),
            PingRecord(date: hours(-25.3), kind: .scheduled, ok: true, resetsAt: hours(-20.3)),
        ]

        switch scene {
        case .running:
            window = UsageReading(percent: 62, resetsAt: hours(3.7), asOf: now)
        case .almostOut:
            window = UsageReading(percent: 94, resetsAt: hours(0.6), asOf: now)
        case .waiting:
            window = nil
        case .problem:
            window = nil
            problem = .signedOut
            setup = .signedOut   // so Connection shows the sign-in step
            history.insert(PingRecord(date: now, kind: .scheduled, ok: false, note: PingError.signedOut.errorDescription), at: 0)
        case .resting:
            window = nil
            week = UsageReading(percent: 100, resetsAt: hours(62), asOf: now)
            weekLimitUntil = hours(62)
        }
    }

    // MARK: - What the menu bar shows

    enum Status { case running, paused, resting, problem }

    var status: Status {
        if attention != nil { return .problem }
        if isPaused { return .paused }
        return isResting ? .resting : .running
    }

    /// What needs your attention, if anything: a failed ping, or Claude Code not being ready.
    var attention: PingError? { problem ?? setup.problem }

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

    /// When Tuloy expects to ping next.
    var upcomingPing: Date? {
        guard !isPaused, !isResting else { return nil }
        // Keep going pings as soon as the open window ends.
        if let resetsAt = currentWindow?.resetsAt, schedule.keepsGoing(at: resetsAt) { return resetsAt }
        return nextPingAt
    }

    var usagePercent: Int? { currentWindow?.percent }
    var lastPing: PingRecord? { history.first }

    /// Where things stand, in one line. Shown large in the Tuloy window and the mini window.
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
        if let attention { return attention.recoverySuggestion ?? "Open Connection to see what's wrong." }
        if isPaused { return "Tuloy won't ping until you resume." }
        if isResting, let week = currentWeek { return "It resets \(Format.time(week.resetsAt)). Tuloy carries on then." }
        if let currentWindow {
            return "Your Claude allowance resets in \(Format.duration(to: currentWindow.resetsAt, from: now))."
        }
        guard let nextPingAt, freshAt != nil else { return "Pick at least one day in Schedule." }
        return "Tuloy pings at \(Format.time(nextPingAt)) to set it up."
    }

    var schedule: Schedule {
        Schedule(freshMinutes: freshMinutes, weekdays: weekdays, keepGoing: keepGoing, untilMinutes: untilMinutes)
    }

    /// The Settings time pickers work with a Date. Tuloy stores minutes.
    var freshTime: Date {
        get { Self.date(forMinutes: freshMinutes) }
        set { freshMinutes = Self.minutes(for: newValue) }
    }

    var untilTime: Date {
        get { Self.date(forMinutes: untilMinutes) }
        set { untilMinutes = Self.minutes(for: newValue) }
    }

    private static func date(forMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(for date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Tuloy's folder, ~/.tuloy. Pings run from here, and the optional status line file lands here.
enum Paths {
    static let tuloy = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".tuloy", directoryHint: .isDirectory)
    static let statusLine = tuloy.appending(path: "statusline.json")
    /// Claude Code's own settings. Tuloy only touches this when you choose Connect in Settings.
    static let claudeSettings = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
}

// MARK: - Saving settings

/// Where settings are kept. Demo mode gets its own, emptied at every start, so it never touches yours.
/// (UserDefaults is safe to use from any thread; Swift just can't see that.)
nonisolated(unsafe) private let store: UserDefaults = {
    let demo = "com.edrichsilva.tuloy.demo"
    guard Demo.isOn, let defaults = UserDefaults(suiteName: demo) else { return .standard }
    defaults.removePersistentDomain(forName: demo)
    return defaults
}()

/// Reads a saved value, or returns `value` if there isn't one yet.
private func saved<T>(_ key: String, default value: T) -> T {
    store.object(forKey: key) as? T ?? value
}

private func save(_ value: Any?, _ key: String) {
    store.set(value, forKey: key)
}

private func savedJSON<T: Decodable>(_ key: String) -> T? {
    store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
}

private func saveJSON<T: Encodable>(_ value: T?, _ key: String) {
    store.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
}

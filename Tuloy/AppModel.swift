import AppKit
import Network
import Observation

/// The Engine, plus everything that ties it to this Mac and its screens:
/// the 30-second loop, waking and reconnecting, the windows, and live usage.
///
/// The thinking is all in Engine.swift. This file is the wiring.
@MainActor
@Observable
final class AppModel: Engine {
    /// The one model, shared by the menu bar, every window, and the app delegate.
    /// Demo mode (and every test) gets pretend sockets: nothing real is run, sent or saved.
    static let shared: AppModel = {
        if Demo.isOn {
            let claude = DemoClaude()
            let model = AppModel(clock: SystemClock(), claude: claude, storage: MemoryStorage(), notices: SilentNotices())
            model.demoClaude = claude
            model.show(.running)
            return model
        }
        return AppModel(clock: SystemClock(), claude: RealClaude(), storage: PreferencesStorage(), notices: SystemNotices())
    }()

    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var demoClaude: DemoClaude?

    // MARK: - Settings for the screens (saved automatically)

    var displayMode = DisplayMode.classic {
        didSet { if isLoaded { storage.set(displayMode.rawValue, for: "displayMode") } }
    }

    /// Show the Tuloy window when you open the app (but not when it starts by itself at login).
    var openAtLaunch = true {
        didSet { if isLoaded { storage.set(openAtLaunch, for: "openAtLaunch") } }
    }

    /// Show the small always-on-top window whenever Tuloy starts.
    var miniAtLaunch = false {
        didSet { if isLoaded { storage.set(miniAtLaunch, for: "miniAtLaunch") } }
    }

    /// True the first time Tuloy runs, so it can open the welcome window.
    var isFirstLaunch = true {
        didSet { if isLoaded { storage.set(!isFirstLaunch, for: "hasLaunched") } }
    }

    // MARK: - Windows

    /// Windows waiting to be opened. The menu bar item opens them, since only a view can.
    var windowRequests: [WindowID] = []
    /// The screen showing in the main window.
    var mainTab = MainTab.home

    // MARK: - Live usage

    /// When Claude Code's status line last saved live usage, if it's connected.
    private(set) var liveUsageAt: Date?
    /// True when Claude Code's status line runs Tuloy's script (Connection, step 4).
    private(set) var isLiveUsageConnected = false
    /// Why connecting or disconnecting didn't work, if it didn't.
    private(set) var liveUsageError: String?

    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private var folderWatch: DispatchSourceFileSystemObject?
    /// Held open for as long as Tuloy runs, so a second copy can tell.
    @ObservationIgnored private var runningLock: Int32?

    init(clock: any Clock, claude: any ClaudeCode, storage: any Storage, notices: any Notices) {
        super.init(clock: clock, claude: claude, storage: storage, notices: notices, calendar: .current)
        displayMode = DisplayMode(rawValue: storage.load("displayMode", default: "")) ?? .classic
        openAtLaunch = storage.load("openAtLaunch", default: true)
        miniAtLaunch = storage.load("miniAtLaunch", default: false)
        isFirstLaunch = !storage.load("hasLaunched", default: false)
        isLoaded = true
    }

    // MARK: - Starting up

    /// Starts the loop and everything that feeds it. Called once, when the app has launched.
    func start() {
        startClock()
        guard !Demo.isOn else { return }

        try? FileManager.default.createDirectory(at: Paths.tuloy, withIntermediateDirectories: true)
        // Keeps the 30-second clock on time while Tuloy sits in the menu bar. Your Mac can still sleep.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Tuloy ping schedule")
        if notify || warnNearlyOut || warnWeek { notices.requestPermission() }
        tickOnWake()
        tickWhenOnline()
        replanWhenTimeZoneChanges()
        watchForSignIn()
        refreshLiveUsage()
        Task { await checkSetup() }
    }

    /// Checks the clock every 30 seconds instead of setting one long timer,
    /// so sleep and shutdown can't throw the schedule off.
    private func startClock() {
        Task {
            while true {
                readLiveUsage()
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
            Task { @MainActor in self?.timeZoneChanged() }
        }
    }

    // MARK: - Signing in

    /// Opens Terminal on Claude Code's own sign-in. You sign in there, in your browser;
    /// Tuloy never sees your login. Returns false if Terminal couldn't be opened.
    @discardableResult
    func signInWithTerminal() async -> Bool {
        if let demoClaude {
            demoClaude.setSignedIn(true)
            pretendSignedIn()
            return true
        }
        guard let claude = await ClaudeCLI.locator.find() else { return false }
        do {
            try FileManager.default.createDirectory(at: Paths.tuloy, withIntermediateDirectories: true)
            try ClaudeCLI.signInScript(for: claude, marker: Paths.signedInMarker)
                .write(to: Paths.signInScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Paths.signInScript.path(percentEncoded: false))
        } catch {
            return false
        }
        return NSWorkspace.shared.open(Paths.signInScript)
    }

    /// The sign-in script leaves a marker in Tuloy's folder when it finishes. macOS tells Tuloy the
    /// moment the folder changes, so the step turns green without a click and without checking on a timer.
    private func watchForSignIn() {
        let folder = Darwin.open(Paths.tuloy.path(percentEncoded: false), O_EVTONLY)
        guard folder >= 0 else { return }
        let watch = DispatchSource.makeFileSystemObjectSource(fileDescriptor: folder, eventMask: .write, queue: .main)
        watch.setEventHandler { [weak self] in
            Task { @MainActor in await self?.signInFinished() }
        }
        watch.setCancelHandler { close(folder) }
        watch.resume()
        folderWatch = watch
    }

    private func signInFinished() async {
        let marker = Paths.signedInMarker.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: marker) else { return }
        // Tidy up: the marker has done its job, and so has the script.
        try? FileManager.default.removeItem(at: Paths.signedInMarker)
        try? FileManager.default.removeItem(at: Paths.signInScript)

        await checkSetup()
        if case .ready = setup {
            say("Signed in. Send a test ping to finish.")
        } else {
            say("Claude Code still isn't signed in. Try Sign In again.", good: false)
        }
        open(.main, tab: .connection)
    }

    // MARK: - Live usage

    /// Picks up usage saved by Claude Code's status line, if you've connected it (see README).
    private func readLiveUsage() {
        guard !Demo.isOn, let modified = StatusLineFile.modified, modified > (liveUsageAt ?? .distantPast),
              let live = StatusLineFile.read(asOf: modified)
        else { return }

        liveUsageAt = modified
        take(window: live.window, week: live.week)
    }

    /// Connects or disconnects Claude Code's status line, the source of live usage.
    func setLiveUsage(connected: Bool) {
        guard !Demo.isOn else {
            isLiveUsageConnected = connected
            say(connected ? "Live usage connected." : "Live usage disconnected.")
            return
        }
        do {
            if connected { try StatusLineLink().connect() } else { try StatusLineLink().disconnect() }
            liveUsageError = nil
            say(connected ? "Live usage connected." : "Live usage disconnected.")
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

    // MARK: - Windows

    /// Asks for a window to be opened and brought to the front.
    func open(_ window: WindowID, tab: MainTab? = nil) {
        if let tab { mainTab = tab }
        windowRequests.append(window)
    }

    /// Decides what to show when Tuloy starts: the welcome the first time, the main
    /// window when you opened the app yourself, nothing when it started by itself at login.
    func didLaunch(atLogin: Bool) {
        if !Demo.isOn, !isOnlyCopy() {
            // Another Tuloy is already running and pinging. Bring it forward and bow out.
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            others.first { $0 != .current }?.activate()
            NSApp.terminate(nil)
            return
        }
        start()
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

    /// True if this is the only real Tuloy running. (Demo mode doesn't count, and isn't counted.)
    private func isOnlyCopy() -> Bool {
        try? FileManager.default.createDirectory(at: Paths.tuloy, withIntermediateDirectories: true)
        runningLock = OnlyCopy.claim(at: Paths.tuloy.appending(path: "running.lock"))
        return runningLock != nil
    }

    // MARK: - Demo mode

    override func show(_ scene: Demo.Scene) {
        demoClaude?.setSignedIn(scene != .problem)
        super.show(scene)
    }
}

/// Tuloy's folder, ~/.tuloy. Pings run from here, and the optional status line file lands here.
enum Paths {
    static let tuloy = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".tuloy", directoryHint: .isDirectory)
    static let statusLine = tuloy.appending(path: "statusline.json")
    /// The script Terminal runs for Sign In, and the marker it leaves when it's done.
    static let signInScript = tuloy.appending(path: "Sign in to Claude Code.command")
    static let signedInMarker = tuloy.appending(path: "signed-in")
    /// Claude Code's own settings. Tuloy only touches this when you choose Connect.
    static let claudeSettings = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
}

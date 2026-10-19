import Foundation
import Testing
@testable import Tuloy

// MARK: - Pretend sockets

/// A clock the test sets by hand.
final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var time: Date

    init(_ time: Date) { self.time = time }

    var now: Date {
        get { lock.withLock { time } }
        set { lock.withLock { time = newValue } }
    }
}

/// A Claude Code that does what the test tells it, and counts what it was asked.
final class ScriptedClaude: ClaudeCode, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: TestClock
    private var queued: [PingOutcome] = []
    private var always: PingOutcome?
    private var setupNow = ClaudeSetup.ready(plan: "pro")
    private var versionNow = "2.1.288"
    private var counts = (pings: 0, checks: 0)
    private var memories: [PingMemory?] = []

    init(clock: TestClock) { self.clock = clock }

    var pings: Int { lock.withLock { counts.pings } }
    var checks: Int { lock.withLock { counts.checks } }
    /// What the Engine said it remembered, at the most recent ping.
    var lastMemory: PingMemory? { lock.withLock { memories.last ?? nil } }

    var setup: ClaudeSetup {
        get { lock.withLock { setupNow } }
        set { lock.withLock { setupNow = newValue } }
    }

    var versionNumber: String {
        get { lock.withLock { versionNow } }
        set { lock.withLock { versionNow = newValue } }
    }

    /// The next pings come to these, in order. After that, pings work.
    func next(_ outcomes: PingOutcome...) { lock.withLock { queued += outcomes } }
    /// Every ping fails this way until `works()`.
    func alwaysFails(_ error: PingError) { lock.withLock { always = PingOutcome(result: .failure(error), style: .lean, version: versionNow) } }
    func works() { lock.withLock { always = nil; queued = [] } }

    func ping(remembering memory: PingMemory?) async -> PingOutcome {
        lock.withLock {
            counts.pings += 1
            memories.append(memory)
            if let always { return always }
            if !queued.isEmpty { return queued.removeFirst() }
            return PingOutcome(result: .success(freshWindow()), style: memory?.style ?? .lean, version: versionNow)
        }
    }

    func checkSetup() async -> ClaudeSetup { lock.withLock { counts.checks += 1; return setupNow } }
    func locate() async -> String? { "~/.local/bin/claude" }
    func version() async -> String? { lock.withLock { versionNow } }

    /// What a real ping reports when it opens a window: a start rounded down to 10 minutes, and 0% used.
    func freshWindow(percent: Int? = 0) -> PingReport {
        let now = clock.now
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 600).rounded(.down) * 600)
        return PingReport(window: UsageReading(percent: percent, resetsAt: start.addingTimeInterval(Schedule.window), asOf: now), tokens: 350)
    }
}

final class RecordingNotices: Notices {
    var posted: [(id: String, title: String, body: String)] = []
    var freshAt: Date?
    var permissionAsked = false

    func requestPermission() { permissionAsked = true }
    func freshWindow(at date: Date?) { freshAt = date }
    func post(_ id: String, title: String, body: String) { posted.append((id, title, body)) }
    func count(_ id: String) -> Int { posted.filter { $0.id == id }.count }
}

/// A whole pretend world: Monday 5 October 2026, 4:00 AM, fresh window wanted at 11:00 every day.
@MainActor
struct World {
    let clock = TestClock(october(5, 4))
    let claude: ScriptedClaude
    let storage = MemoryStorage()
    let notices = RecordingNotices()
    let engine: Engine

    init(_ settings: [String: Any] = [:]) {
        claude = ScriptedClaude(clock: clock)
        for (key, value) in settings { storage.set(value, for: key) }
        engine = Engine(clock: clock, claude: claude, storage: storage, notices: notices, calendar: calendar)
    }

    /// Jumps to a time and lets the Engine look, as if the Mac had just woken.
    func go(to date: Date) async {
        clock.now = date
        await engine.tick()
    }

    /// Lets time pass, with the Engine looking every 30 seconds as the app does.
    func run(until end: Date) async {
        while clock.now < end {
            clock.now = clock.now.addingTimeInterval(30)
            await engine.tick()
        }
    }

    /// A second Engine on the same saved state, as after quitting and reopening.
    func restarted() -> Engine {
        Engine(clock: clock, claude: claude, storage: storage, notices: notices, calendar: calendar)
    }

    func failure(_ error: PingError, version: String? = nil) -> PingOutcome {
        PingOutcome(result: .failure(error), style: .lean, version: version ?? claude.versionNumber)
    }

    func reading(_ percent: Int?, resets: Date, ago: TimeInterval = 0) -> UsageReading {
        UsageReading(percent: percent, resetsAt: resets, asOf: clock.now.addingTimeInterval(-ago))
    }
}

// MARK: - What Tuloy does with a ping (the scenarios from brainstorm.txt)

@MainActor
@Suite struct EngineTests {
    let due = october(5, 6, 0, 15)

    // 1
    @Test func aScheduledPingSavesTheWindowAndPlansTheNext() async {
        let world = World()
        await world.go(to: october(5, 6))
        #expect(world.claude.pings == 0)

        await world.go(to: due)
        #expect(world.claude.pings == 1)
        #expect(world.engine.window?.resetsAt == october(5, 11))
        #expect(world.engine.nextPingAt == october(6, 6, 0, 15))
        #expect(world.engine.history.map(\.ok) == [true])
        #expect(world.engine.history.first?.tokens == 350)
        #expect(world.engine.windows.map(\.openedBy) == [.tuloy])
        #expect(world.notices.freshAt == october(5, 11))
        #expect(world.engine.notice?.text.hasPrefix("Pinged. Fresh window at") == true)
    }

    // 2
    @Test func aPingWithNoReportBecomesAnEstimate() async {
        let world = World()
        world.claude.next(PingOutcome(result: .success(PingReport()), style: .lean, version: "2.1.288"))
        await world.go(to: due)
        #expect(world.engine.window?.isEstimate == true)
        #expect(world.engine.window?.resetsAt == due.addingTimeInterval(Schedule.window))
    }

    // 3
    @Test func aPingAtTheWindowLimitStillCounts() async {
        let world = World()
        var report = world.claude.freshWindow(percent: 100)
        report.blockedBy = .window
        world.clock.now = due
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.engine.tick()
        #expect(world.engine.history.first?.ok == true)
        #expect(world.engine.usagePercent == 100)
        #expect(world.engine.problem == nil)
    }

    // 4
    @Test func aUsedUpWeekMeansRestNotRetries() async {
        let world = World()
        let weekResets = october(7, 20)
        let report = PingReport(week: UsageReading(percent: 100, resetsAt: weekResets, asOf: due), blockedBy: .week)
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.go(to: due)
        await world.run(until: october(5, 9))

        #expect(world.claude.pings == 1)
        #expect(world.engine.isResting)
        #expect(world.engine.history.map(\.ok) == [false])
        #expect(world.engine.forecast == Forecast(date: weekResets, reason: .resting))
    }

    // 5
    @Test func aDuePingWaitsForTheInternet() async {
        let world = World()
        world.engine.isOnline = false
        await world.go(to: due)
        await world.run(until: october(5, 6, 30))
        #expect(world.claude.pings == 0)

        world.engine.isOnline = true
        await world.engine.tick()
        #expect(world.claude.pings == 1)
    }

    // 6
    @Test func aFailureThatFixesItselfIsRetriedAndBacksOff() async {
        let world = World()
        world.claude.alwaysFails(.timedOut)
        world.clock.now = due.addingTimeInterval(-30)
        await world.run(until: october(5, 7))

        let minutes = world.engine.history.reversed().map { Int($0.date.timeIntervalSince(due) / 60) }
        #expect(minutes == [0, 1, 3, 8, 23, 53])   // after 1, 2, 5, 15, then 30 minutes
        #expect(world.engine.waitingOn == nil)
        #expect(world.notices.count("problem") == 0)   // nothing for you to do
        #expect(world.engine.forecast.reason == .retrying)
    }

    // 7
    @Test func aFailureOnlyYouCanFixIsTriedOnce() async {
        let world = World()
        world.claude.alwaysFails(.signedOut)
        world.claude.setup = .signedOut
        world.clock.now = due.addingTimeInterval(-30)
        await world.run(until: october(5, 9))

        #expect(world.claude.pings == 1)
        #expect(world.engine.waitingOn == .signedOut)
        #expect(world.notices.count("problem") == 1)
        // The free check looks in every 5 minutes for the first hour, then every half hour.
        #expect((12...17).contains(world.claude.checks))
        #expect(world.engine.forecast.reason == .waitingOnYou(.signedOut))
    }

    // 8
    @Test func signingInIsFollowedByOnePing() async {
        let world = World()
        world.claude.alwaysFails(.signedOut)
        world.claude.setup = .signedOut
        await world.go(to: due)
        await world.run(until: october(5, 7))
        #expect(world.claude.pings == 1)

        // You sign in. The script's marker makes Tuloy check at once.
        world.claude.works()
        world.claude.setup = .ready(plan: "pro")
        await world.engine.checkSetup()
        #expect(world.engine.waitingOn == nil)
        #expect(world.engine.problem == nil)

        await world.run(until: october(5, 7, 1))
        #expect(world.claude.pings == 2)
        #expect(world.engine.history.first?.ok == true)
    }

    // 9
    @Test func aMacThatWakesTwoHoursLateStillPings() async {
        let world = World()
        await world.go(to: october(5, 8))
        #expect(world.claude.pings == 1)
        #expect(world.engine.window?.resetsAt == october(5, 13))
        #expect(world.engine.currentPlanNote?.contains("went out late") == true)
    }

    // 10
    @Test func aMacThatWakesSixHoursLateSkipsToTomorrow() async {
        let world = World()
        await world.go(to: october(5, 12, 10))
        #expect(world.claude.pings == 0)
        #expect(world.engine.nextPingAt == october(6, 6, 0, 15))
    }

    // 11
    @Test func aPingWaitsForAnOpenWindowToEnd() async {
        let world = World()
        world.clock.now = october(5, 5)
        world.engine.take(window: world.reading(40, resets: october(5, 8)), week: nil)   // you were up late

        await world.go(to: due)
        await world.go(to: october(5, 8, 0, 30))
        #expect(world.claude.pings == 0)

        await world.go(to: october(5, 8, 1))
        #expect(world.claude.pings == 1)
        #expect(world.engine.window?.resetsAt == october(5, 13))
        #expect(world.engine.currentPlanNote?.contains("waited for it to end") == true)
    }

    // 12
    @Test func keepGoingPingsAtEachResetUntilTheStopTime() async {
        let world = World(["keepGoing": true])   // until 6:00 PM
        await world.run(until: october(5, 23))

        #expect(world.engine.history.reversed().map(\.kind) == [.scheduled, .keepGoing, .keepGoing])
        let hours = world.engine.history.reversed().map { calendar.component(.hour, from: $0.date) }
        #expect(hours == [6, 11, 16])
    }

    // 13
    @Test func aRefreshDoesNotCancelAScheduledPingThatIsWaiting() async {
        let world = World()
        world.clock.now = october(5, 5)
        let open = world.reading(40, resets: october(5, 8))
        world.engine.take(window: open, week: nil)
        await world.go(to: october(5, 6, 30))   // the scheduled ping is due, but waiting for 8:00

        // You refresh. The ping lands in the window that's already open, so it has started nothing.
        world.claude.next(PingOutcome(result: .success(PingReport(window: world.reading(41, resets: october(5, 8)), tokens: 350)),
                                      style: .lean, version: "2.1.288"))
        await world.engine.refreshUsage()
        #expect(world.engine.notice?.text.contains("already open") == true)
        #expect(world.engine.nextPingAt == due)   // still waiting, not put off till tomorrow

        await world.run(until: october(5, 9))
        #expect(world.claude.pings == 2)   // and it goes out when the window ends
        #expect(world.engine.history.first?.kind == .scheduled)
        #expect(world.engine.window?.resetsAt == october(5, 13))
        #expect(world.engine.nextPingAt == october(6, 6, 0, 15))
    }

    @Test func pingNowThatOpensAWindowCoversAScheduledPing() async {
        let world = World()
        world.claude.next(world.failure(.timedOut))
        await world.go(to: due)   // the scheduled ping fails; Tuloy will retry in a minute
        world.clock.now = due.addingTimeInterval(30)
        await world.engine.pingNow()   // you don't wait: your ping opens the window

        #expect(world.engine.nextPingAt == october(6, 6, 0, 15))
        await world.run(until: october(5, 6, 30))
        #expect(world.claude.pings == 2)   // no third ping
    }

    @Test func theRefreshArrowNeverStartsAWindow() async {
        let world = World()
        await world.engine.refreshUsage()   // no window open
        #expect(world.claude.pings == 0)
        #expect(world.engine.notice?.text.hasPrefix("No window is open") == true)

        world.engine.take(window: world.reading(40, resets: october(5, 8)), week: nil)
        world.claude.next(PingOutcome(result: .success(PingReport(window: world.reading(42, resets: october(5, 8)), tokens: 350)),
                                      style: .lean, version: "2.1.288"))
        await world.engine.refreshUsage()   // a window is open: this only updates the number
        #expect(world.claude.pings == 1)
        #expect(world.engine.usagePercent == 42)
    }

    @Test func aWindowStartedByHandSaysWhatItDoesToTheSchedule() async {
        let world = World()   // 4:00 AM; the scheduled ping is at 6:00
        await world.engine.pingNow()
        #expect(world.engine.window?.resetsAt == october(5, 9))
        #expect(world.engine.notice?.text.contains("will wait for this window to end") == true)

        await world.run(until: october(5, 9, 2))
        #expect(world.claude.pings == 2)   // the scheduled ping waited, then went at 9:01
        #expect(world.engine.history.first?.kind == .scheduled)
    }

    @Test func aPingAtTheLimitSaysTheWindowIsUsedUp() async {
        let world = World()
        world.clock.now = due
        var report = world.claude.freshWindow(percent: 100)
        report.blockedBy = .window
        report.tokens = 0
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.engine.tick()

        #expect(world.engine.notice?.text.hasPrefix("This window is used up.") == true)
        let record = try! #require(world.engine.history.first)
        #expect(record.hitTheLimit)
        #expect(record.mark == "–")
        #expect(record.outcomeText.hasPrefix("Window used up, resets"))
    }

    // 14
    @Test func nothingIsSentLateAfterAPause() async {
        let world = World()
        world.clock.now = october(5, 5)
        world.engine.togglePause()
        #expect(world.engine.notice?.text.hasPrefix("Paused.") == true)
        await world.run(until: october(5, 7))
        #expect(world.claude.pings == 0)
        #expect(world.engine.forecast.reason == .paused)

        world.engine.togglePause()
        #expect(world.engine.notice?.text.hasPrefix("Resumed.") == true)
        await world.run(until: october(5, 7, 30))
        #expect(world.claude.pings == 0)
        #expect(world.engine.nextPingAt == october(6, 6, 0, 15))
    }

    // 15
    @Test func changingTheScheduleClearsARetryAndPlansAgain() async {
        let world = World()
        world.claude.next(world.failure(.timedOut), world.failure(.timedOut), world.failure(.timedOut), world.failure(.timedOut))
        world.clock.now = due.addingTimeInterval(-30)
        await world.run(until: october(5, 6, 20))   // four tries; the next would be at 6:23
        #expect(world.claude.pings == 4)

        world.engine.freshMinutes = 11 * 60 + 30    // fresh at 11:30, so ping at 6:30
        #expect(world.engine.nextPingAt == october(5, 6, 30, 15))
        #expect(world.engine.notice?.text.hasPrefix("Saved.") == true)
        await world.run(until: october(5, 6, 31))
        #expect(world.claude.pings == 5)
        #expect(world.engine.history.first?.ok == true)
    }

    // 16
    @Test func theCommandThatWorkedIsRemembered() async {
        let world = World()
        world.clock.now = due
        world.claude.next(PingOutcome(result: .success(world.claude.freshWindow()), style: .plain, version: "2.0.0"))
        await world.engine.tick()
        #expect(world.engine.pingMemory == PingMemory(style: .plain, version: "2.0.0"))

        await world.go(to: october(6, 6, 0, 15))
        #expect(world.claude.lastMemory == PingMemory(style: .plain, version: "2.0.0"))
        #expect(world.restarted().pingMemory == world.engine.pingMemory)   // and survives a restart
    }

    // 17
    @Test func aFailureRightAfterAnUpdateSaysSo() async {
        let world = World()
        await world.go(to: due)
        #expect(world.engine.pingMemory?.version == "2.1.288")

        world.claude.versionNumber = "2.2.0"
        world.claude.next(world.failure(.loginNotUsed, version: "2.2.0"))
        await world.go(to: october(6, 6, 0, 15))
        #expect(world.engine.problemNote == "This started after Claude Code updated from 2.1.288 to 2.2.0.")
        #expect(world.engine.detail.contains("2.2.0"))
    }

    @Test func aFailureOnTheSameVersionBlamesNoUpdate() async {
        let world = World()
        await world.go(to: due)
        world.claude.next(world.failure(.loginNotUsed))
        await world.go(to: october(6, 6, 0, 15))
        #expect(world.engine.problem == .loginNotUsed)
        #expect(world.engine.problemNote == nil)
    }

    // MARK: - The day it really happened

    /// 5 October 2026: Claude Code was signed out, keep going was on, and the old rules tried again
    /// and again for three hours. Now: one automatic try, then the free check until you sign in.
    @Test func replayOfTheSignedOutAfternoon() async {
        let world = World(["freshMinutes": 16 * 60, "keepGoing": true, "untilMinutes": 23 * 60])
        world.claude.alwaysFails(.signedOut)
        world.claude.setup = .signedOut
        world.clock.now = october(5, 16, 42)
        await world.run(until: october(5, 19, 43))

        #expect(world.claude.pings == 1)   // it was 8 on the day
        #expect(world.notices.count("problem") == 1)
        #expect(world.engine.history.count == 1)
    }

    // MARK: - Other retry rules

    @Test func aRefusedLoginIsTriedAgainOnlyAtTheNextScheduledTime() async {
        let world = World(["keepGoing": true])
        world.claude.alwaysFails(.loginNotUsed)
        world.clock.now = due.addingTimeInterval(-30)
        await world.run(until: october(6, 5, 59))
        #expect(world.claude.pings == 1)   // a whole day, keep going on, and not one more try

        await world.run(until: october(6, 6, 1))
        #expect(world.claude.pings == 2)
    }

    @Test func anOldClaudeCodeIsLeftAloneUntilItChanges() async {
        let world = World()
        world.claude.versionNumber = "1.0.0"
        world.claude.alwaysFails(.unknownOption)
        world.clock.now = due.addingTimeInterval(-30)
        await world.run(until: october(5, 8))
        #expect(world.claude.pings == 1)
        #expect(world.engine.waitingOn == .unknownOption)

        world.claude.versionNumber = "2.1.288"   // you ran "claude update"
        world.claude.works()
        await world.run(until: october(5, 8, 31))
        #expect(world.claude.pings == 2)
        #expect(world.engine.problem == nil)
    }

    @Test func aCheckThatSaysSignedOutMeansNoPingIsWasted() async {
        let world = World()
        world.claude.setup = .signedOut
        await world.engine.checkSetup()
        await world.go(to: due)
        #expect(world.claude.pings == 0)
        #expect(world.engine.attention == .signedOut)
    }

    @Test func pingNowWorksWhateverTheState() async {
        let world = World()
        world.claude.setup = .signedOut
        await world.engine.checkSetup()
        world.engine.togglePause()
        await world.engine.pingNow()
        #expect(world.claude.pings == 1)
    }

    // MARK: - The morning health check

    @Test func aSignOutIsReportedBeforeThePingItWouldBreak() async {
        let world = World()
        world.claude.setup = .signedOut
        await world.go(to: october(5, 4, 59))
        #expect(world.claude.checks == 0)

        await world.run(until: october(5, 7))
        #expect(world.notices.count("health") == 1)
        #expect(world.notices.posted.first?.body.contains("6:00") == true)
        #expect(world.claude.pings == 0)   // and no ping wasted finding out
    }

    @Test func aHealthyMorningSaysNothing() async {
        let world = World()
        await world.run(until: october(5, 5, 30))
        #expect(world.claude.checks == 1)
        #expect(world.notices.posted.isEmpty)
    }

    // MARK: - Nearly out

    @Test func nearlyOutIsAnnouncedOncePerLevel() async {
        let world = World()
        let resets = october(5, 9)
        world.engine.take(window: world.reading(79, resets: resets), week: nil)
        #expect(world.notices.count("nearly-out") == 0)

        world.clock.now = october(5, 4, 1)
        world.engine.take(window: world.reading(81, resets: resets), week: nil)
        #expect(world.notices.count("nearly-out") == 1)
        #expect(world.notices.posted.last?.title == "80% of this window used")

        world.clock.now = october(5, 4, 2)
        world.engine.take(window: world.reading(82, resets: resets), week: nil)
        #expect(world.notices.count("nearly-out") == 1)

        world.clock.now = october(5, 4, 3)
        world.engine.take(window: world.reading(96, resets: resets), week: nil)
        #expect(world.notices.count("nearly-out") == 2)
        #expect(world.notices.posted.last?.title == "95% of this window used")
    }

    @Test func aNewWindowStartsTheCountAgainAndARestartDoesNotRepeat() async {
        let world = World()
        world.engine.take(window: world.reading(85, resets: october(5, 9)), week: nil)
        #expect(world.notices.count("nearly-out") == 1)

        // Quit and reopen: the same reading must not be announced again.
        let reopened = world.restarted()
        world.clock.now = october(5, 4, 1)
        reopened.take(window: world.reading(86, resets: october(5, 9)), week: nil)
        #expect(world.notices.count("nearly-out") == 1)

        world.clock.now = october(5, 9, 5)
        reopened.take(window: world.reading(85, resets: october(5, 14)), week: nil)
        #expect(world.notices.count("nearly-out") == 2)
    }

    @Test func nearlyOutStaysQuietWhenItCannotHelp() async {
        let world = World()
        world.engine.take(window: world.reading(90, resets: october(5, 9), ago: 11 * 60), week: nil)   // an old reading
        world.engine.take(window: world.reading(90, resets: october(5, 4, 8)), week: nil)              // resets in 8 minutes
        #expect(world.notices.count("nearly-out") == 0)

        world.engine.warnNearlyOut = false
        world.clock.now = october(5, 4, 10)
        world.engine.take(window: world.reading(97, resets: october(5, 9, 10)), week: nil)
        #expect(world.notices.count("nearly-out") == 0)
    }

    @Test func theWeekIsAnnouncedToo() async {
        let world = World()
        world.engine.take(window: nil, week: world.reading(83, resets: october(7, 20)))
        #expect(world.notices.count("week-nearly-out") == 1)
        #expect(world.notices.posted.last?.title == "Your week is 80% used")
    }

    // MARK: - The forecast never promises what won't happen

    @Test func theForecastAgreesWithWhatActuallyHappens() async {
        // Each of these leaves the Engine in a different state. In every one, a ping must go out
        // at the forecast time and not a moment before.
        let setups: [@MainActor (World) async -> Void] = [
            { _ in },                                                                    // nothing yet: scheduled
            { $0.clock.now = october(5, 5); $0.engine.take(window: $0.reading(40, resets: october(5, 8)), week: nil)
              await $0.go(to: october(5, 6, 30)) },                                      // waiting for a window
            { $0.claude.next($0.failure(.timedOut)); await $0.go(to: october(5, 6, 0, 15)) },   // retrying
            { await $0.go(to: october(5, 6, 0, 15)) },                                   // pinged: tomorrow's next
            { await $0.go(to: october(5, 12, 10)) },                                     // skipped
        ]
        for keepGoing in [false, true] {
            for setUp in setups {
                let world = World(["keepGoing": keepGoing])
                await setUp(world)
                let forecast = world.engine.forecast
                let date = try! #require(forecast.date)
                let before = world.claude.pings

                if date > world.clock.now.addingTimeInterval(1) {
                    await world.go(to: date.addingTimeInterval(-1))
                    #expect(world.claude.pings == before, "pinged before the forecast (\(forecast.reason))")
                }
                await world.go(to: date)
                #expect(world.claude.pings == before + 1, "no ping at the forecast time (\(forecast.reason))")
            }
        }
    }

    @Test func theForecastSaysWhy() async {
        let world = World(["keepGoing": true])
        #expect(world.engine.forecast == Forecast(date: due, reason: .scheduled(fresh: october(5, 11))))
        #expect(world.engine.forecast.sentence(now: world.clock.now).contains("5 hours before your"))

        await world.go(to: due)
        #expect(world.engine.forecast == Forecast(date: october(5, 11, 1), reason: .keepGoing))
        #expect(world.engine.forecast.sentence(now: world.clock.now).hasSuffix("when this window ends"))

        world.engine.weekdays = []
        world.clock.now = october(5, 11, 30)
        await world.engine.tick()
        #expect(world.engine.forecast.date == nil)
    }
}

// MARK: - The small rules

@Suite struct PingMemoryTests {
    private func outcome(_ style: PingStyle, _ version: String?) -> PingOutcome {
        PingOutcome(result: .success(PingReport()), style: style, version: version)
    }

    @Test func remembersWhatWorked() {
        #expect(PingMemory.after(outcome(.lean, "2.1"), previous: nil) == PingMemory(style: .lean, version: "2.1"))
        #expect(PingMemory.after(outcome(.plain, "2.0"), previous: nil) == PingMemory(style: .plain, version: "2.0"))
    }

    @Test func givesTheSmallPingAnotherTryAfterAnUpdate() {
        let plain = PingMemory(style: .plain, version: "2.0")
        #expect(PingMemory.after(outcome(.plain, "2.0"), previous: plain) == plain)
        #expect(PingMemory.after(outcome(.plain, "2.1"), previous: plain) == nil)   // forget: try the small one next
    }

    @Test func fallsBackOnlyWhenTheFlagsCouldBeToBlame() {
        let worked = PingMemory(style: .lean, version: "2.1")
        // A flag this Claude Code doesn't know: always worth the plain command.
        #expect(PingMemory.mayFallBack(after: .unknownOption, memory: worked, version: "2.1"))
        // The small ping has worked on this version: a sign-out isn't the flags' fault.
        #expect(!PingMemory.mayFallBack(after: .signedOut, memory: worked, version: "2.1"))
        #expect(!PingMemory.mayFallBack(after: .failed("odd"), memory: worked, version: "2.1"))
        // Never worked here, or Claude Code has changed: the flags are suspects again.
        #expect(PingMemory.mayFallBack(after: .signedOut, memory: nil, version: "2.1"))
        #expect(PingMemory.mayFallBack(after: .failed("odd"), memory: worked, version: "2.2"))
        // Never for things that plainly aren't the flags.
        #expect(!PingMemory.mayFallBack(after: .offline, memory: nil, version: nil))
        #expect(!PingMemory.mayFallBack(after: .timedOut, memory: nil, version: nil))
    }
}

@Suite struct LocatorTests {
    /// A pretend disk: which paths hold a runnable claude, and how many times Tuloy searched.
    private final class Disk: @unchecked Sendable {
        private let lock = NSLock()
        private var runnable: Set<String> = []
        private var place: String?
        private var count = 0

        var searches: Int { lock.withLock { count } }
        func install(at path: String?) { lock.withLock { place = path; runnable = path.map { [$0] } ?? [] } }
        func isRunnable(_ path: String) -> Bool { lock.withLock { runnable.contains(path) } }
        func search() -> URL? { lock.withLock { count += 1; return place.map { URL(fileURLWithPath: $0) } } }
    }

    @Test func searchesOnceThenRemembers() async {
        let disk = Disk()
        disk.install(at: "/opt/a/claude")
        let locator = Locator(isRunnable: disk.isRunnable, search: { disk.search() })

        for _ in 0..<5 { #expect(await locator.find()?.path == "/opt/a/claude") }
        #expect(disk.searches == 1)
    }

    @Test func searchesAgainWhenItMoves() async {
        let disk = Disk()
        disk.install(at: "/opt/a/claude")
        let locator = Locator(isRunnable: disk.isRunnable, search: { disk.search() })
        _ = await locator.find()

        disk.install(at: "/opt/b/claude")   // reinstalled somewhere else
        #expect(await locator.find()?.path == "/opt/b/claude")
        #expect(disk.searches == 2)
    }

    @Test func trustsWhatItRememberedFromLastTime() async {
        let disk = Disk()
        disk.install(at: "/opt/a/claude")
        let locator = Locator(remembered: "/opt/a/claude", isRunnable: disk.isRunnable, search: { disk.search() })
        #expect(await locator.find()?.path == "/opt/a/claude")
        #expect(disk.searches == 0)
    }

    @Test func saysSoWhenItIsNotInstalled() async {
        let disk = Disk()
        let locator = Locator(isRunnable: disk.isRunnable, search: { disk.search() })
        #expect(await locator.find() == nil)
    }
}

@Suite struct ReadingAgeTests {
    let now = october(5, 15)

    @Test func saysHowOldAReadingIs() {
        #expect(Format.age(of: now, now: now) == "just now")
        #expect(Format.age(of: now.addingTimeInterval(-119), now: now) == "just now")
        #expect(Format.age(of: now.addingTimeInterval(-6 * 60), now: now) == "6 min ago")
        #expect(Format.age(of: now.addingTimeInterval(-15 * 60), now: now) == "15 min ago")
        #expect(Format.age(of: now.addingTimeInterval(-16 * 60), now: now).hasPrefix("as of "))
    }

    @Test func readsVersionsEvenFromAFailedPing() {
        let output = """
        {"type":"system","subtype":"init","claude_code_version":"2.1.288","model":"claude-haiku-4-5"}
        {"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate"}
        """
        #expect(PingOutput.version(in: output) == "2.1.288")
        #expect(PingOutput.version(in: "not json") == nil)
    }
}

@Suite struct OnlyCopyTests {
    @Test func aSecondTuloyIsTurnedAway() throws {
        let lock = FileManager.default.temporaryDirectory.appending(path: "tuloy-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: lock) }

        let first = try #require(OnlyCopy.claim(at: lock))
        #expect(OnlyCopy.claim(at: lock) == nil)   // already running

        close(first)                               // the first one quits
        let next = try #require(OnlyCopy.claim(at: lock))
        close(next)
    }
}

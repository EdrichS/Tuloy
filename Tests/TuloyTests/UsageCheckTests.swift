import Foundation
import Testing
@testable import Tuloy

/// The free usage check: Claude Code's own `/usage`, every 5 minutes.
@MainActor
@Suite struct UsageCheckTests {

    @Test func checksEveryFiveMinutes() async {
        let world = World()
        await world.run(until: october(5, 4, 30))
        #expect(world.claude.usageChecks == 6)   // 4:00:30, 4:05:30, ... 4:25:30
        #expect(world.claude.pings == 0)
    }

    @Test func aCheckFillsInTheWindowAndTheWeek() async {
        let world = World()
        world.claude.nextUsage(world.usage(window: world.reading(63, resets: october(5, 6, 50)),
                                           week: world.reading(29, resets: october(8, 20))))
        await world.engine.tick()

        #expect(world.engine.usagePercent == 63)
        #expect(world.engine.currentWeek?.percent == 29)
        // Tuloy didn't open it, so it's yours.
        #expect(world.engine.windows.last?.openedBy == .you)
        #expect(world.claude.pings == 0)
    }

    @Test func aWindowYouOpenedHoldsBackTheScheduledPing() async {
        let world = World()   // 4:00 AM; the scheduled ping is at 6:00
        world.clock.now = october(5, 5, 10)
        world.claude.nextUsage(world.usage(window: world.reading(5, resets: october(5, 10, 10))))
        await world.engine.tick()

        await world.run(until: october(5, 9))
        #expect(world.claude.pings == 0)   // known before 6:00, so no ping went into the open window
        #expect(world.engine.forecast.reason == .waitingForWindow(until: october(5, 10, 10)))
    }

    @Test func nothingIsCheckedWhileSwitchedOff() async {
        let world = World(["checksUsage": false])
        await world.run(until: october(5, 5))
        #expect(world.claude.usageChecks == 0)
    }

    @Test func nothingIsCheckedWhileClaudeCodeNeedsYou() async {
        let world = World()
        world.claude.setup = .signedOut
        await world.engine.checkSetup()
        await world.run(until: october(5, 4, 30))
        #expect(world.claude.usageChecks == 0)
    }

    @Test func aCheckThatCostTokensStopsAllChecking() async {
        let world = World()
        world.claude.nextUsage(UsageOutcome(result: .failure(.failed("ok")), tokens: 350, wasFree: false))
        await world.engine.tick()
        #expect(world.engine.usageCheckCost == 350)
        #expect(world.notices.count("usage-check") == 1)

        await world.run(until: october(5, 5))
        #expect(world.claude.usageChecks == 1)   // never again

        // Until you switch it back on.
        world.engine.checksUsage = false
        world.engine.checksUsage = true
        #expect(world.engine.usageCheckCost == nil)
        await world.engine.tick()
        #expect(world.claude.usageChecks == 2)
    }

    @Test func aFailedCheckIsQuietAndTriedAgainLater() async {
        let world = World()
        world.claude.nextUsage(UsageOutcome(result: .failure(.offline)))
        await world.engine.tick()
        #expect(world.engine.usageCheckTrouble == PingError.offline.errorDescription)
        #expect(world.notices.posted.isEmpty)
        #expect(world.engine.notice == nil)

        await world.run(until: october(5, 4, 6))
        #expect(world.claude.usageChecks == 2)
        #expect(world.engine.usageCheckTrouble == nil)
    }

    @Test func noWindowClearsAnOldGuessButNotAFreshPing() async {
        let world = World()
        await world.go(to: october(5, 6, 0, 15))   // the scheduled ping opens a window until 11:00
        #expect(world.engine.currentWindow != nil)

        // Claude's figures can lag a ping by a few minutes. That mustn't wipe the window out.
        world.clock.now = october(5, 6, 5)
        world.claude.nextUsage(world.usage(noWindow: true))
        await world.engine.checkUsage()
        #expect(world.engine.currentWindow != nil)

        // Well after, Claude Code still says none is open (limits were reset early): believe it.
        world.clock.now = october(5, 6, 30)
        world.claude.nextUsage(world.usage(noWindow: true))
        await world.engine.checkUsage()
        #expect(world.engine.currentWindow == nil)
    }

    @Test func lastKnownFiguresAreNotTaken() async {
        let world = World()
        var report = UsageReport(window: world.reading(90, resets: october(5, 6)))
        report.isLastKnown = true
        world.claude.nextUsage(UsageOutcome(result: .success(report)))
        await world.engine.tick()
        #expect(world.engine.currentWindow == nil)
        #expect(world.engine.usageCheckTrouble == nil)
    }

    @Test func nearlyOutIsAnnouncedFromAFreeCheck() async {
        let world = World()
        world.claude.nextUsage(world.usage(window: world.reading(83, resets: october(5, 6))))
        await world.engine.tick()
        #expect(world.notices.count("nearly-out") == 1)
    }

    @Test func resetTimesFromTheCheckAndFromPingsAreTheSameWindow() async {
        let world = World()
        await world.go(to: october(5, 6, 0, 15))   // the ping says the window resets at 11:00:00
        let fromCheck = october(5, 11).addingTimeInterval(0.36)   // /usage says 11:00:00.36
        world.clock.now = october(5, 6, 10)
        world.claude.nextUsage(world.usage(window: world.reading(12, resets: fromCheck)))
        await world.engine.checkUsage()

        #expect(world.engine.windows.count == 1)
        #expect(world.engine.windows.last?.openedBy == .tuloy)
    }

    @Test func windowsNeverOverlapOnTheTodayBar() async {
        let world = World()
        await world.go(to: october(5, 6, 0, 15))   // Tuloy's window: 6:00 to 11:00
        // Later Claude says a window began at 8:50 (limits were reset early, or the first reading was off).
        world.clock.now = october(5, 9)
        world.claude.nextUsage(world.usage(window: world.reading(3, resets: october(5, 13, 50))))
        await world.engine.checkUsage()

        let windows = world.engine.windows
        #expect(windows.count == 2)
        #expect(windows[0].end == october(5, 8, 50))   // cut short where the new one began
        #expect(windows[1].start == october(5, 8, 50))
        #expect(world.engine.currentWindow?.resetsAt == october(5, 13, 50))
    }

    // MARK: - Resting

    @Test func restingIsRememberedAcrossARestart() async {
        let world = World()
        let weekResets = october(7, 20)
        let report = PingReport(week: UsageReading(percent: 100, resetsAt: weekResets, asOf: due), blockedBy: .week)
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.go(to: due)
        #expect(world.engine.isResting)

        let again = world.restarted()
        #expect(again.isResting)
        world.clock.now = october(6, 6, 0, 15)   // the next scheduled ping
        await again.tick()
        #expect(world.claude.pings == 1)   // no ping spent finding out again
    }

    @Test func restingEndsWhenTheWeekHasRoomAgain() async {
        let world = World()
        let report = PingReport(week: UsageReading(percent: 100, resetsAt: october(7, 20), asOf: due), blockedBy: .week)
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.go(to: due)
        #expect(world.engine.isResting)

        // Anthropic resets limits early: the check shows room in the week.
        world.clock.now = october(5, 9)
        world.claude.nextUsage(world.usage(week: world.reading(0, resets: october(12, 20))))
        await world.engine.checkUsage()
        #expect(!world.engine.isResting)
    }

    @Test func restingRunsToTheRealReset() async {
        let world = World()
        // The refused ping didn't say when the week resets, so Tuloy guessed an hour.
        let report = PingReport(blockedBy: .week)
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.go(to: due)
        #expect(world.engine.weekLimitUntil == due.addingTimeInterval(3600))

        world.clock.now = due.addingTimeInterval(600)
        world.claude.nextUsage(world.usage(week: world.reading(100, resets: october(7, 20))))
        await world.engine.checkUsage()
        #expect(world.engine.weekLimitUntil == october(7, 20))
    }

    @Test func aUsedUpWeekSeenByTheCheckMeansRest() async {
        let world = World()
        world.claude.nextUsage(world.usage(week: world.reading(100, resets: october(7, 20))))
        await world.engine.tick()
        #expect(world.engine.isResting)
        await world.run(until: october(5, 9))
        #expect(world.claude.pings == 0)   // the 6:00 ping would only have been turned away
    }

    // MARK: - Extra usage: a ping must never be paid for

    @Test func noPingWhileALimitIsUsedUpAndExtraUsageIsOn() async {
        let world = World()
        var report = UsageReport(window: world.reading(100, resets: october(5, 6)))
        report.extraUsageOn = true
        world.claude.nextUsage(UsageOutcome(result: .success(report)))
        await world.engine.tick()
        #expect(world.engine.extraUsageOn == true)
        #expect(world.engine.wouldBePaid)

        await world.engine.pingNow()
        #expect(world.claude.pings == 0)
        #expect(world.engine.notice?.text.hasPrefix("Not sent") == true)

        // Once the window resets, pinging is free of charge again.
        await world.run(until: october(5, 6, 2))
        #expect(!world.engine.wouldBePaid)
        #expect(world.claude.pings == 1)
    }

    @Test func withExtraUsageOffAPingAtTheLimitIsSent() async {
        let world = World()
        var report = UsageReport(window: world.reading(100, resets: october(5, 6)))
        report.extraUsageOn = false
        world.claude.nextUsage(UsageOutcome(result: .success(report)))
        await world.engine.tick()
        #expect(!world.engine.wouldBePaid)
        await world.engine.pingNow()   // turned away for free, as before
        #expect(world.claude.pings == 1)
    }

    @Test func aPaidPingIsFlaggedAtOnce() async {
        let world = World()
        var report = world.claude.freshWindow()
        report.usedExtraUsage = true
        world.claude.next(PingOutcome(result: .success(report), style: .lean, version: "2.1.288"))
        await world.engine.pingNow()
        #expect(world.engine.history.first?.note == "Paid from extra usage")
        #expect(world.notices.count("extra-usage") == 1)
        #expect(world.engine.extraUsageOn == true)
    }

    // MARK: - An API key: a ping must never be billed

    @Test func anAPIKeyInClaudeCodesSettingsStopsEveryPing() async {
        let world = World()
        var keyed = world.usage()
        keyed.usesAPIKey = true
        world.claude.nextUsage(keyed)
        world.claude.usageAlways(keyed)
        await world.engine.tick()
        #expect(world.engine.apiKeyInUse)
        #expect(world.engine.attention == .notOnPlan)
        #expect(world.notices.count("problem") == 1)

        await world.engine.pingNow()
        #expect(world.engine.notice?.text.hasPrefix("Not sent") == true)
        // The sign-in check still says your plan (the key came from Claude Code's settings), but
        // Claude Code's own report wins: no scheduled ping either.
        await world.run(until: october(5, 9))
        #expect(world.claude.pings == 0)
        #expect(world.engine.forecast.reason == .waitingOnYou(.notOnPlan))
    }

    @Test func pingsCarryOnOnceTheKeyIsGone() async {
        let world = World()
        var keyed = world.usage()
        keyed.usesAPIKey = true
        world.claude.nextUsage(keyed)
        await world.engine.tick()
        #expect(world.engine.apiKeyInUse)

        // You removed the key. The next look (free) says so.
        world.claude.usageAlways(world.usage())
        await world.run(until: october(5, 6, 2))
        #expect(!world.engine.apiKeyInUse)
        #expect(world.engine.attention == nil)
        #expect(world.claude.pings == 1)   // the 6:00 ping went out, on your plan
    }

    @Test func aPingThatReportsAnAPIKeyStopsTheNext() async {
        let world = World()
        var outcome = world.failure(.notOnPlan)
        outcome.usedAPIKey = true
        world.claude.next(outcome)
        await world.go(to: due)
        #expect(world.engine.apiKeyInUse)
        await world.engine.pingNow()
        #expect(world.claude.pings == 1)
    }

    private var due: Date { october(5, 6, 0, 15) }
}

/// What Tuloy keeps of its pings: a month in full, a year of daily counts.
@MainActor
@Suite struct HistoryTests {

    @Test func keepsAMonth() async {
        let world = World()
        for day in 5...30 { await world.go(to: october(day, 6, 0, 15)) }
        #expect(world.engine.history.count == 26)   // far more than the old 20

        let later = october(5, 4).addingTimeInterval(40 * 24 * 3600)   // 14 November
        world.clock.now = later
        await world.engine.pingNow()
        let cutoff = later.addingTimeInterval(-Engine.historyKept)
        let kept = (5...30).filter { october($0, 6, 0, 15) > cutoff }.count
        #expect(kept == 17)
        #expect(world.engine.history.count == kept + 1)
        // The day counts outlast the list.
        #expect(world.engine.pingDays["2026-10-05"]?.sent == 1)
    }

    @Test func countsEachDay() async {
        let world = World()
        await world.go(to: october(5, 6, 0, 15))
        world.clock.now = october(5, 12)
        await world.engine.pingNow()
        world.claude.next(world.failure(.offline))
        world.clock.now = october(5, 16)
        await world.engine.pingNow()

        let day = world.engine.pingDays["2026-10-05"]
        #expect(day == PingDay(sent: 2, failed: 1, byYou: 1))
    }

    @Test func differentFailuresStaySeparate() async {
        let world = World()
        world.claude.next(world.failure(.timedOut), world.failure(.offline))
        await world.engine.pingNow()
        await world.engine.pingNow()
        #expect(world.engine.history.count == 2)
    }

    @Test func aSuccessEndsARun() async {
        let world = World()
        world.claude.next(world.failure(.offline), world.failure(.offline))
        await world.engine.pingNow()
        await world.engine.pingNow()
        world.clock.now = october(5, 4, 10)
        await world.engine.pingNow()   // works
        world.claude.next(world.failure(.offline))
        world.clock.now = october(5, 9, 10)
        await world.engine.pingNow()

        #expect(world.engine.history.map { $0.count ?? 1 } == [1, 1, 2])
        #expect(world.engine.pingDays["2026-10-05"]?.failed == 3)
    }

    @Test func dayCountsAreWorkedOutForAnOlderHistory() {
        let storage = MemoryStorage()
        let old = [PingRecord(date: october(4, 6), kind: .scheduled, ok: true),
                   PingRecord(date: october(3, 6), kind: .scheduled, ok: false, count: 3)]
        storage.saveJSON(old, for: "history")
        let clock = TestClock(october(5, 4))
        let engine = Engine(clock: clock, claude: ScriptedClaude(clock: clock), storage: storage, notices: RecordingNotices(), calendar: calendar)
        #expect(engine.pingDays["2026-10-04"] == PingDay(sent: 1))
        #expect(engine.pingDays["2026-10-03"] == PingDay(failed: 3))
    }

    // MARK: - Late pings

    @Test func aPingAfterSleepIsMarkedLate() async {
        let world = World()
        await world.run(until: october(5, 5, 50))
        await world.go(to: october(5, 7, 12))   // asleep from 5:50 to 7:12

        let ping = world.engine.history.first
        #expect(ping?.late == PingRecord.Lateness(due: october(5, 6, 0, 15), reason: .asleep))
        #expect(world.engine.currentPlanNote?.contains("your Mac was asleep at 6:00") == true)
        #expect(world.engine.currentPlanNote?.contains("so the ping went out at 7:12") == true)
    }

    @Test func aPingAfterStartingUpIsMarkedLate() async {
        let world = World()
        world.storage.set(october(5, 6, 0, 15), for: "nextPingAt")
        world.clock.now = october(5, 7, 30)   // the Mac was off; Tuloy starts at 7:30
        let engine = world.restarted()
        await engine.tick()
        #expect(engine.history.first?.late?.reason == .notRunning)
    }

    @Test func anOnTimePingIsNotLate() async {
        let world = World()
        await world.run(until: october(5, 6, 2))
        #expect(world.engine.history.first?.late == nil)
        #expect(world.engine.history.first?.kind == .scheduled)
    }

    @Test func aRetryIsNotCalledLate() async {
        let world = World()
        world.claude.next(world.failure(.timedOut), world.failure(.timedOut), world.failure(.timedOut))
        await world.run(until: october(5, 6, 20))
        #expect(world.engine.history.first?.ok == true)
        #expect(world.engine.history.first?.late == nil)
    }

    // MARK: - The 10-minute mark (choice 6: say so afterwards)

    @Test func anOddMinuteSaysWhatYouGotInstead() async {
        let world = World(["freshMinutes": 10 * 60 + 7])   // fresh window at 10:07
        await world.run(until: october(5, 5, 9))

        // Pinged at 5:07; Claude counts the window from 5:00, so it resets at 10:00.
        // (Times are written with a narrow space before AM.)
        let note = (world.engine.currentPlanNote ?? "").replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(note.hasPrefix("10:00 AM, not 10:07 AM"))
        #expect(note.contains("10-minute mark"))
    }

    @Test func aRoundTimeSaysNothing() async {
        let world = World()
        await world.run(until: october(5, 6, 2))
        #expect(world.engine.currentPlanNote == nil)
    }
}

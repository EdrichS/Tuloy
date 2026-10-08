import Foundation
import Testing
@testable import Tuloy

@Suite struct PlannerTests {
    /// Fresh at 11:00 AM every day, with Monday's ping still to come.
    var planner = Planner(schedule: Schedule(), nextPingAt: october(5, 6, 0, 15))

    private func decide(_ planner: Planner, at date: Date) -> Planner.Decision {
        planner.decide(at: date, calendar: calendar)
    }

    // MARK: - The scheduled ping

    @Test func waitsUntilThePingIsDue() {
        #expect(decide(planner, at: october(5, 6)) == .wait)
    }

    @Test func pingsWhenDue() {
        #expect(decide(planner, at: october(5, 6, 0, 15)) == .ping(.scheduled))
    }

    @Test func catchesUpAfterSleepIfItCanStillHelp() {
        #expect(decide(planner, at: october(5, 8)) == .ping(.scheduled))
    }

    @Test func skipsAPingMissedByMoreThanFiveHours() {
        #expect(decide(planner, at: october(5, 11, 0, 15)) == .skip)
    }

    @Test mutating func doesNothingWhilePaused() {
        planner.isPaused = true
        #expect(decide(planner, at: october(5, 8)) == .wait)
    }

    // MARK: - A window that's already open

    @Test mutating func waitsForAnOpenWindowToEnd() {
        planner.windowResetsAt = october(5, 8)   // you were up late: a window is open until 8:00
        #expect(decide(planner, at: october(5, 7)) == .wait)
        #expect(decide(planner, at: october(5, 8, 0, 30)) == .wait)   // just reset: give it a minute
        #expect(decide(planner, at: october(5, 8, 1)) == .ping(.scheduled))
    }

    @Test mutating func givesUpIfTheOpenWindowOutlastsTheChance() {
        planner.windowResetsAt = october(5, 12)
        #expect(decide(planner, at: october(5, 11, 0, 15)) == .skip)
    }

    // MARK: - Retries

    @Test mutating func holdsOffAfterAFailedPing() {
        planner.holdUntil = october(5, 6, 5)
        #expect(decide(planner, at: october(5, 6, 4)) == .wait)
        #expect(decide(planner, at: october(5, 6, 5)) == .ping(.scheduled))
    }

    @Test func retriesQuicklyThenBacksOff() {
        #expect(Planner.retryDelay(afterFailures: 1) == 60)
        #expect(Planner.retryDelay(afterFailures: 2) == 120)
        #expect(Planner.retryDelay(afterFailures: 3) == 300)
        #expect(Planner.retryDelay(afterFailures: 4) == 900)
        #expect(Planner.retryDelay(afterFailures: 5) == 1800)
        #expect(Planner.retryDelay(afterFailures: 50) == 1800)
        #expect(Planner.retryDelay(afterFailures: 0) == 60)
    }

    // MARK: - Keep going

    /// Monday's ping went out, and the window it opened resets at 11:00.
    private var afterMorningPing: Planner {
        var planner = planner
        planner.nextPingAt = october(6, 6, 0, 15)
        planner.windowResetsAt = october(5, 11)
        return planner
    }

    @Test func leavesTheRestOfTheDayAloneByDefault() {
        #expect(decide(afterMorningPing, at: october(5, 11, 1)) == .wait)
    }

    @Test func keepGoingStartsANewWindowWhenOneEnds() {
        var planner = afterMorningPing
        planner.schedule.keepGoing = true
        #expect(decide(planner, at: october(5, 10, 59)) == .wait)
        #expect(decide(planner, at: october(5, 11, 0, 30)) == .wait)
        #expect(decide(planner, at: october(5, 11, 1)) == .ping(.keepGoing))
    }

    @Test func keepGoingStopsAtTheStopTime() {
        var planner = afterMorningPing
        planner.schedule.keepGoing = true   // until 6:00 PM
        planner.windowResetsAt = october(5, 16)
        #expect(decide(planner, at: october(5, 16, 1)) == .ping(.keepGoing))
        planner.windowResetsAt = october(5, 21)
        #expect(decide(planner, at: october(5, 21, 1)) == .wait)
    }

    @Test func keepGoingWaitsWhileOnHold() {
        var planner = afterMorningPing
        planner.schedule.keepGoing = true
        planner.holdUntil = october(5, 11, 10)
        #expect(decide(planner, at: october(5, 11, 5)) == .wait)
    }
}

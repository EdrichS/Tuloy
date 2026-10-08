import Foundation
import Testing
@testable import Tuloy

@Suite struct ScheduleTests {
    let schedule = Schedule()   // fresh at 11:00 AM, every day

    // MARK: - The scheduled ping

    @Test func pingsFiveHoursBeforeTheFreshWindow() {
        #expect(schedule.nextPing(after: october(5, 5), calendar: calendar) == october(5, 6, 0, 15))
    }

    @Test func movesToTomorrowOnceTodaysPingHasPassed() {
        #expect(schedule.nextPing(after: october(5, 6, 1), calendar: calendar) == october(6, 6, 0, 15))
    }

    @Test func skipsDaysThatAreSwitchedOff() {
        var schedule = schedule
        schedule.weekdays = [2, 3, 4, 5, 6]   // Monday to Friday
        // Friday the 9th, after that day's ping: the next one is Monday the 12th.
        #expect(schedule.nextPing(after: october(9, 7), calendar: calendar) == october(12, 6, 0, 15))
    }

    @Test func pingsTheNightBeforeAnEarlyFreshWindow() {
        var schedule = schedule
        schedule.freshMinutes = 2 * 60   // 2:00 AM
        schedule.weekdays = [3]          // Tuesday
        #expect(schedule.nextPing(after: october(4, 12), calendar: calendar) == october(5, 21, 0, 15))
        #expect(schedule.pingTimeText.hasSuffix("the night before"))
    }

    @Test func plansNothingWithNoDays() {
        var schedule = schedule
        schedule.weekdays = []
        #expect(schedule.nextPing(after: october(5, 5), calendar: calendar) == nil)
        #expect(schedule.nextFresh(after: october(5, 5), calendar: calendar) == nil)
    }

    @Test func findsTheNextFreshWindow() {
        #expect(schedule.nextFresh(after: october(5, 7), calendar: calendar) == october(5, 11))
        #expect(schedule.nextFresh(after: october(5, 12), calendar: calendar) == october(6, 11))
    }

    // MARK: - Keep going

    @Test func plansOneWindowWithoutKeepGoing() {
        let windows = schedule.windows(endingFirstAt: october(5, 11), calendar: calendar)
        #expect(windows == [DateInterval(start: october(5, 6), end: october(5, 11))])
    }

    @Test func keepGoingChainsWindowsUntilTheStopTime() {
        var schedule = schedule
        schedule.keepGoing = true   // until 6:00 PM
        let starts = schedule.windows(endingFirstAt: october(5, 11), calendar: calendar).map(\.start)
        #expect(starts == [october(5, 6), october(5, 11), october(5, 16)])
    }

    @Test func keepGoingOnlyRunsBetweenTheFreshWindowAndTheStopTime() {
        var schedule = schedule
        schedule.keepGoing = true
        #expect(!schedule.keepsGoing(at: october(5, 10, 59), calendar: calendar))
        #expect(schedule.keepsGoing(at: october(5, 11), calendar: calendar))
        #expect(schedule.keepsGoing(at: october(5, 17, 59), calendar: calendar))
        #expect(!schedule.keepsGoing(at: october(5, 18), calendar: calendar))
    }

    @Test func keepGoingRestsOnDaysThatAreSwitchedOff() {
        var schedule = schedule
        schedule.keepGoing = true
        schedule.weekdays = [2, 3, 4, 5, 6]
        #expect(!schedule.keepsGoing(at: october(10, 12), calendar: calendar))   // Saturday
    }

    @Test func keepGoingCanRunPastMidnight() {
        var schedule = schedule
        schedule.keepGoing = true
        schedule.freshMinutes = 22 * 60   // 10:00 PM
        schedule.untilMinutes = 3 * 60    // 3:00 AM
        #expect(schedule.stopTime(after: october(5, 22), calendar: calendar) == october(6, 3))
        #expect(schedule.keepsGoing(at: october(6, 2), calendar: calendar))
        #expect(!schedule.keepsGoing(at: october(6, 3), calendar: calendar))
    }

    @Test func keepGoingNeverGetsInTheWayOfTomorrowsPing() {
        var schedule = schedule
        schedule.keepGoing = true
        schedule.untilMinutes = schedule.freshMinutes   // around the clock
        // A window started at 2:00 AM would still be open at the 6:00 AM ping, so it's left out.
        let starts = schedule.windows(endingFirstAt: october(5, 11), calendar: calendar).map(\.start)
        #expect(starts == [october(5, 6), october(5, 11), october(5, 16), october(5, 21)])
    }
}

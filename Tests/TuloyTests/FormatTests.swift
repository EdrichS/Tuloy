import Foundation
import Testing
@testable import Tuloy

@Suite struct FormatTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func countsDownInHoursThenMinutes() {
        #expect(Format.countdown(to: now.addingTimeInterval(5 * 3600 - 1), from: now) == "4:59")
        #expect(Format.countdown(to: now.addingTimeInterval(3600), from: now) == "1:00")
        #expect(Format.countdown(to: now.addingTimeInterval(45 * 60), from: now) == "45m")
        #expect(Format.countdown(to: now.addingTimeInterval(30), from: now) == "<1m")
    }

    @Test func theRingCountsWholeHoursThenMinutes() {
        let left = { (minutes: Double) in Format.ringCountdown(to: self.now.addingTimeInterval(minutes * 60), from: self.now) }
        #expect(left(300) == "5h")
        #expect(left(299.5) == "5h")
        #expect(left(241) == "5h")
        #expect(left(240) == "4h")
        #expect(left(181) == "4h")
        #expect(left(180) == "3h")
        #expect(left(121) == "3h")
        #expect(left(120) == "120")   // from here, minutes
        #expect(left(119.2) == "120")   // rounded up: never less time than there is
        #expect(left(45) == "45")
        #expect(left(1) == "1")
        #expect(left(0.25) == "1")
        #expect(left(-3) == "1")
        #expect(left(16 * 60) == "16h")   // the next fresh window, while none is open
        #expect(left(62 * 60) == "3d")   // a weekly rest
        #expect(Format.ringCountdown(to: nil, from: now) == "–")
    }

    @Test func neverCountsBelowZero() {
        #expect(Format.countdown(to: now.addingTimeInterval(-600), from: now) == "<1m")
    }

    @Test func showsADashWithNothingToCountTo() {
        #expect(Format.countdown(to: nil, from: now) == "–")
    }

    @Test func percentagesStayInRange() {
        #expect(UsageReading.clampedPercent(23.5) == 24)
        #expect(UsageReading.clampedPercent(-3) == 0)
        #expect(UsageReading.clampedPercent(140) == 100)
    }

    @Test func readsUnixTimeInSecondsOrMilliseconds() {
        #expect(Date(unixTime: 1_790_000_000) == now)
        #expect(Date(unixTime: 1_790_000_000_000) == now)
    }
}

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

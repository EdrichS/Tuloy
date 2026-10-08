import Foundation

/// A fixed calendar, so tests give the same answer on any Mac.
let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// A time in October 2026. The 5th is a Monday.
func october(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
}

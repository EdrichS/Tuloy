import Foundation

/// Demo mode: Tuloy with made-up data, for trying it out or taking screenshots.
///
/// Start it with `make demo` (or pass `--demo` to the app). It sends no pings, never runs
/// Claude Code, shows no notifications, and keeps its settings apart from yours. The menu
/// gains a Demo Scene submenu for switching between the states Tuloy can be in.
enum Demo {
    /// Also on whenever this code runs inside some other program, such as the test runner,
    /// so a test can never send a ping or touch your settings. Only Tuloy itself does real things.
    static let isOn = CommandLine.arguments.contains("--demo") || ProcessInfo.processInfo.processName != "Tuloy"
    /// Add `--setup` to see the welcome window instead of the main one.
    static let showsSetup = CommandLine.arguments.contains("--setup")

    enum Scene: String, CaseIterable, Identifiable {
        case running = "Window Open"
        case almostOut = "Almost Out"
        case waiting = "No Window Yet"
        case problem = "Needs Attention"
        case resting = "Weekly Limit Used Up"

        var id: Self { self }
    }

    /// A pretend ping: a short wait, then a fresh 5-hour window.
    static func ping() async -> PingReport {
        try? await Task.sleep(for: .seconds(1))
        let now = Date()
        return PingReport(window: UsageReading(percent: 0, resetsAt: now.addingTimeInterval(Schedule.window), asOf: now))
    }
}

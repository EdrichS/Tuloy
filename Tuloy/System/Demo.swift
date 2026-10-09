import Foundation

/// Demo mode: Tuloy with made-up data, for trying it out or taking screenshots.
///
/// Start it with `make demo` (or pass `--demo` to the app). It sends no pings, never runs
/// Claude Code, shows no notifications, and saves nothing. The panel's menu gains a
/// Demo Scene submenu for switching between the states Tuloy can be in.
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
}

/// A pretend Claude Code for demo mode: pings "work" after a second, and nothing leaves the Mac.
final class DemoClaude: ClaudeCode, @unchecked Sendable {
    private let lock = NSLock()
    private var signedIn = true

    /// The "Needs Attention" scene is a signed-out Claude Code, until you choose Sign In.
    func setSignedIn(_ value: Bool) {
        lock.withLock { signedIn = value }
    }

    func ping(remembering memory: PingMemory?) async -> PingOutcome {
        try? await Task.sleep(for: .seconds(1))
        guard lock.withLock({ signedIn }) else {
            return PingOutcome(result: .failure(.signedOut), style: .lean, version: "2.1.288")
        }
        let now = Date()
        let window = UsageReading(percent: 0, resetsAt: now.addingTimeInterval(Schedule.window), asOf: now)
        return PingOutcome(result: .success(PingReport(window: window, tokens: 350)), style: .lean, version: "2.1.288")
    }

    func checkSetup() async -> ClaudeSetup {
        lock.withLock { signedIn } ? .ready(plan: "pro") : .signedOut
    }

    func locate() async -> String? { "~/.local/bin/claude" }
    func version() async -> String? { "2.1.288" }
}

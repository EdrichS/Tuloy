import Foundation

// The four sockets the Engine plugs into. The app plugs in the real ones
// (the Mac's clock, the claude command, saved preferences, macOS notifications).
// Tests plug in pretend ones, so every situation can be played out in a second.

/// Tells the time.
protocol Clock: Sendable {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

/// Everything Tuloy asks of Claude Code.
protocol ClaudeCode: Sendable {
    /// Sends one ping. `memory` is what worked last time, so it never runs a command
    /// already known not to be the problem.
    func ping(remembering memory: PingMemory?) async -> PingOutcome
    /// Checks that Claude Code is installed and signed in, without sending a message.
    func checkSetup() async -> ClaudeSetup
    /// Where the `claude` command is, for showing in Connection.
    func locate() async -> String?
    /// Claude Code's version, such as "2.1.288".
    func version() async -> String?
}

/// The two ways of sending a ping: the small one with newer flags, and the plain one any version knows.
enum PingStyle: String, Codable, Sendable {
    case lean, plain
}

/// What a ping came to, and how it was sent.
struct PingOutcome: Sendable {
    var result: Result<PingReport, PingError>
    var style: PingStyle
    /// Claude Code's version, when its output said.
    var version: String?
}

/// Which ping command last worked, and on which Claude Code.
struct PingMemory: Codable, Equatable, Sendable {
    var style: PingStyle
    var version: String?

    /// What to remember after a ping that got through.
    static func after(_ outcome: PingOutcome, previous: PingMemory?) -> PingMemory? {
        // The plain command worked, but Claude Code has changed since: forget, so the
        // small one gets another try next time. It may have gained the flags.
        if outcome.style == .plain, let previous, previous.style == .plain,
           let version = outcome.version, version != previous.version {
            return nil
        }
        return PingMemory(style: outcome.style, version: outcome.version ?? previous?.version)
    }

    /// After the small ping failed with `error`, is the plain one worth a try?
    static func mayFallBack(after error: PingError, memory: PingMemory?, version: String?) -> Bool {
        // A flag this Claude Code doesn't know: always.
        if error == .unknownOption { return true }
        // The small ping has never worked here, or Claude Code has changed since it did:
        // the newer flags could be to blame for an error Tuloy can't otherwise place.
        let changed = memory?.version != nil && version != nil && memory?.version != version
        return (memory == nil || changed) && error.mayBeTheExtras
    }
}

/// Where settings and state are kept between launches.
protocol Storage: AnyObject {
    func value(for key: String) -> Any?
    func set(_ value: Any?, for key: String)
}

extension Storage {
    /// A saved value, or `fallback` if there isn't one yet.
    func load<T>(_ key: String, default fallback: T) -> T {
        value(for: key) as? T ?? fallback
    }

    func loadJSON<T: Decodable>(_ key: String) -> T? {
        (value(for: key) as? Data).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func saveJSON<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }
}

/// Storage that forgets everything when Tuloy quits. For demo mode and tests.
final class MemoryStorage: Storage {
    private var values: [String: Any] = [:]

    func value(for key: String) -> Any? { values[key] }
    func set(_ value: Any?, for key: String) { values[key] = value }
}

/// Notifications.
protocol Notices: AnyObject {
    func requestPermission()
    /// Schedules the "fresh window" notification for `date`, replacing any earlier one. Nil cancels it.
    func freshWindow(at date: Date?)
    /// Shows a notification now. A later one with the same `id` replaces it.
    func post(_ id: String, title: String, body: String)
}

// MARK: - Small shapes the Engine keeps

/// One line saying what just happened, shown where you're looking for a few seconds.
struct Notice: Equatable, Sendable {
    var text: String
    var isGood: Bool
    var date: Date
}

/// A usage window Tuloy has seen: when it ran, who opened it, and how full it got.
struct WindowRecord: Codable, Equatable, Sendable {
    enum Opener: String, Codable, Sendable {
        /// One of Tuloy's own pings.
        case tuloy
        /// Already running when Tuloy looked: your own use, or your phone's ping.
        case you
    }

    var start: Date
    var end: Date
    var openedBy: Opener
    /// The highest usage seen, 0 to 100.
    var peak: Int?
}

/// Why today's fresh window isn't at the time you asked for.
struct PlanNote: Codable, Equatable, Sendable {
    /// The window this is about, by its reset time.
    var resetsAt: Date
    var text: String
}

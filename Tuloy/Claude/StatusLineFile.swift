import Foundation

/// Live usage, as last saved by Claude Code's status line.
struct LiveUsage: Equatable, Sendable {
    var window: UsageReading?
    var week: UsageReading?
}

/// Optional live usage. Claude Code's status line can save its data to
/// ~/.tuloy/statusline.json (see README), and Tuloy reads it while you work.
enum StatusLineFile {
    /// When the file last changed, or nil if there isn't one.
    static var modified: Date? {
        let path = Paths.statusLine.path(percentEncoded: false)
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Your limits from the file. `asOf` is when the file changed.
    static func read(asOf: Date) -> LiveUsage? {
        guard let data = FileManager.default.contents(atPath: Paths.statusLine.path(percentEncoded: false)) else { return nil }
        return parse(data, asOf: asOf)
    }

    /// Nil if this isn't status line data, or it doesn't include your limits
    /// (Claude Code adds them after the first reply of a session).
    static func parse(_ data: Data, asOf: Date) -> LiveUsage? {
        guard let limits = (try? JSONDecoder().decode(StatusLine.self, from: data))?.rate_limits else { return nil }
        let usage = LiveUsage(window: limits.five_hour?.reading(asOf: asOf), week: limits.seven_day?.reading(asOf: asOf))
        return usage.window == nil && usage.week == nil ? nil : usage
    }

    /// The parts of Claude Code's status line data Tuloy uses.
    private struct StatusLine: Decodable {
        var rate_limits: RateLimits?

        struct RateLimits: Decodable {
            var five_hour: Window?
            var seven_day: Window?
        }

        struct Window: Decodable {
            var used_percentage: Double?   // 0...100
            var resets_at: Double?         // Unix time

            func reading(asOf: Date) -> UsageReading? {
                guard let resets_at else { return nil }
                return UsageReading(
                    percent: used_percentage.map(UsageReading.clampedPercent),
                    resetsAt: Date(unixTime: resets_at),
                    asOf: asOf
                )
            }
        }
    }
}

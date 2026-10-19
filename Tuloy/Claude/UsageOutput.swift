import Foundation

/// What the free usage check found.
struct UsageReport: Equatable, Sendable {
    /// Your 5-hour window, if one is open.
    var window: UsageReading?
    /// True when Claude Code said plainly that no window is open.
    var noWindow = false
    /// Your weekly limit.
    var week: UsageReading?
    /// True when Claude Code couldn't reach its usage service and showed old figures instead.
    var isLastKnown = false
    /// Whether your account has paid extra usage switched on. With it on, a message sent while a
    /// limit is used up is paid for instead of turned away. Nil if Claude Code didn't say.
    var extraUsageOn: Bool?
}

/// What one usage check came to, and whether it was free.
struct UsageOutcome: Sendable {
    var result: Result<UsageReport, PingError>
    /// Tokens the check used, as Claude Code counted them. Always 0 so far.
    var tokens = 0
    /// False if Claude Code passed "/usage" to Claude as a message instead of answering it
    /// itself. That would make every check a ping, so Tuloy stops checking if it ever happens.
    var wasFree = true
    /// Claude Code's version, when its output said.
    var version: String?
    /// True if Claude Code said it's set up with an API key: a ping now would be billed.
    var usesAPIKey = false
}

/// Reads what `claude -p /usage --output-format stream-json --verbose` printed.
///
/// `/usage` is answered by Claude Code itself: no message goes to Claude, no tokens are used,
/// and no window starts. Its figures come in a `usage_report` on the reply line, like this:
///
///     "usage_report": {"rate_limits": {"limits": [
///       {"kind": "session", "group": "session", "percent": 75, "resets_at": "2026-10-19T05:50:00.364551+00:00"},
///       {"kind": "weekly_all", "group": "weekly", "percent": 29, "resets_at": "2026-10-22T00:00:00.364575+00:00"}]}}
enum UsageOutput {

    static func read(_ output: String, status: Int32 = 0, errors: String = "", asOf: Date) -> UsageOutcome {
        let events = StreamEvent.lines(in: output)
        let result = events.last { $0.type == "result" }
        let tokens = result?.tokens ?? 0
        let wasFree = tokens == 0 && (result?.numTurns ?? 0) == 0
        let version = PingOutput.version(in: output)
        let usesAPIKey = PingOutput.usesAPIKey(in: output)

        guard let limits = events.lazy.compactMap(\.usageReport?.rateLimits?.limits).first, status == 0, result?.isError != true else {
            let message = result?.result ?? result?.errors?.first ?? errors
            let error = message.isEmpty || events.contains(where: { $0.usageReport != nil })
                ? PingError.failed(status == 0 ? "Claude Code didn't report your usage." : "Claude Code exited with code \(status).")
                : PingError(message: message)
            return UsageOutcome(result: .failure(error), tokens: tokens, wasFree: wasFree, version: version, usesAPIKey: usesAPIKey)
        }

        var report = UsageReport()
        report.isLastKnown = (result?.result ?? "").localizedCaseInsensitiveContains("last-known")

        if let session = limits.first(where: { $0.kind == "session" || $0.group == "session" }) {
            if let reading = session.reading(asOf: asOf) {
                report.window = reading
            } else {
                // Listed, but with no reset still to come: no window is open.
                report.noWindow = true
            }
        }
        let weekly = limits.first { $0.kind == "weekly_all" } ?? limits.first { $0.group == "weekly" }
        report.week = weekly?.reading(asOf: asOf)
        report.extraUsageOn = events.lazy.compactMap(\.usageReport?.rateLimits?.extraUsage?.isEnabled).first

        return UsageOutcome(result: .success(report), tokens: tokens, wasFree: wasFree, version: version, usesAPIKey: usesAPIKey)
    }

    // MARK: - The JSON

    struct Report: Decodable {
        var rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }

        init(from decoder: Decoder) throws {
            rateLimits = try decoder.container(keyedBy: CodingKeys.self).optional(.rateLimits)
        }
    }

    struct RateLimits: Decodable {
        var limits: [Limit]?
        var extraUsage: ExtraUsage?

        enum CodingKeys: String, CodingKey {
            case limits
            case extraUsage = "extra_usage"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // One odd entry shouldn't cost the others.
            let entries: [Lenient<Limit>]? = values.optional(.limits)
            limits = entries?.compactMap(\.value)
            extraUsage = values.optional(.extraUsage)
        }
    }

    struct ExtraUsage: Decodable {
        var isEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
        }

        init(from decoder: Decoder) throws {
            isEnabled = try decoder.container(keyedBy: CodingKeys.self).optional(.isEnabled)
        }
    }

    struct Limit: Decodable {
        var kind: String?
        var group: String?
        /// 0 to 100.
        var percent: Double?
        var resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent
            case resetsAt = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            kind = values.optional(.kind)
            group = values.optional(.group)
            percent = values.optional(.percent)
            if let text: String = values.optional(.resetsAt) {
                resetsAt = UsageOutput.date(from: text)
            } else if let number: Double = values.optional(.resetsAt) {
                resetsAt = Date(unixTime: number)
            }
        }

        /// A reading, if this limit has a reset still to come. `asOf` is when the check began.
        func reading(asOf: Date) -> UsageReading? {
            guard let resetsAt, resetsAt > asOf else { return nil }
            return UsageReading(percent: percent.map(UsageReading.clampedPercent), resetsAt: resetsAt, asOf: asOf)
        }
    }

    /// Decodes a value, or nil instead of failing.
    struct Lenient<T: Decodable>: Decodable {
        var value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    /// "2026-10-19T05:50:00.364551+00:00", to the whole second. Pings report whole seconds, and
    /// the same window must read the same from both.
    static func date(from text: String) -> Date? {
        var trimmed = text
        if let dot = text.firstIndex(of: ".") {
            let fractionEnd = text[text.index(after: dot)...].firstIndex { !$0.isNumber } ?? text.endIndex
            trimmed = String(text[..<dot]) + String(text[fractionEnd...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

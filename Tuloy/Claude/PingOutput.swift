import Foundation

/// What one ping told Tuloy about your limits.
struct PingReport: Equatable, Sendable {
    /// Your 5-hour window, if Claude Code reported it.
    var window: UsageReading?
    /// Your weekly limit, if Claude Code reported it.
    var week: UsageReading?
    /// The limit that turned the ping away, if one is used up.
    var blockedBy: Limit?
    /// What the ping cost: every token sent and received, as counted by Claude Code.
    var tokens: Int?
    /// True if Claude said the ping was paid from your extra usage, because a limit was used up.
    var usedExtraUsage = false

    enum Limit: Sendable {
        case window, week
    }
}

/// Reads what `claude -p --output-format stream-json` printed: one JSON event per line.
enum PingOutput {

    /// Returns what the ping reported, or throws if it didn't get through.
    static func read(_ output: String, status: Int32 = 0, errors: String = "", now: Date = Date()) throws -> PingReport {
        let events = StreamEvent.lines(in: output)
        let report = limits(in: events, now: now)
        let result = events.last { $0.type == "result" }

        // A report on your window means the ping reached your plan, even if the reply
        // itself failed (for example, when you're already at your limit).
        if report.window != nil || report.blockedBy == .week { return report }
        if status == 0, result?.isError != true { return report }

        let message = result?.result ?? result?.errors?.first ?? errors
        throw PingError(message: message.isEmpty ? "Claude Code exited with code \(status)." : message)
    }

    /// What Claude Code said about your limits, and what the run cost. A ping and a message print the same.
    static func limits(in events: [StreamEvent], now: Date) -> PingReport {
        var report = PingReport()
        for info in events.compactMap(\.rateLimits) {
            if info.isUsingOverage == true { report.usedExtraUsage = true }
            let blocked = info.status == "rejected" ? limit(named: info.rateLimitType, resetsAt: info.resetsAt, now: now) : nil
            if let blocked { report.blockedBy = blocked }

            for (name, window) in info.windows {
                guard let limit = limit(named: name, resetsAt: window.resetsAt, now: now),
                      let resetsAt = window.resetsAt
                else { continue }

                let reading = UsageReading(
                    percent: window.utilization.map(percent) ?? (limit == blocked ? 100 : nil),
                    resetsAt: Date(unixTime: resetsAt),
                    asOf: now
                )
                switch limit {
                case .window: report.window = reading
                case .week: report.week = reading
                }
            }
        }

        report.tokens = events.last { $0.type == "result" }?.tokens
        return report
    }

    /// Claude Code's version, from the first line it prints. It's there even when the ping fails.
    static func version(in output: String) -> String? {
        struct Start: Decodable {
            var claude_code_version: String?
        }
        for line in output.split(whereSeparator: \.isNewline).prefix(20) {
            if let version = (try? JSONDecoder().decode(Start.self, from: Data(line.utf8)))?.claude_code_version { return version }
        }
        return nil
    }

    /// True when Claude Code's first line says it's using an API key rather than your Claude plan
    /// ("apiKeySource" is "none" on a subscription). A ping like that would be billed.
    static func usesAPIKey(in output: String) -> Bool {
        struct Start: Decodable {
            var apiKeySource: String?
        }
        for line in output.split(whereSeparator: \.isNewline).prefix(20) {
            guard let source = (try? JSONDecoder().decode(Start.self, from: Data(line.utf8)))?.apiKeySource else { continue }
            let text = source.lowercased()
            return text != "none" && (text.contains("key") || text.contains("anthropic"))
        }
        return false
    }

    /// Which of your limits a report is about, or nil if it isn't one Tuloy tracks
    /// (or it has already reset, so it says nothing about now).
    private static func limit(named name: String?, resetsAt: Double?, now: Date) -> PingReport.Limit? {
        guard let resetsAt else { return nil }
        let remaining = Date(unixTime: resetsAt).timeIntervalSince(now)
        let fitsWindow = remaining > 0 && remaining <= Schedule.window + 10 * 60
        let fitsWeek = remaining > 0 && remaining <= 7 * 24 * 60 * 60 + 60 * 60

        switch name {
        case "five_hour":
            return fitsWindow ? .window : nil
        case let name? where name.hasPrefix("seven_day"):
            return fitsWeek ? .week : nil
        case nil:
            // Older versions don't name the limit. Tell them apart by how far off the reset is.
            return fitsWindow ? .window : fitsWeek ? .week : nil
        default:
            return nil
        }
    }

    /// Claude Code reports usage as a fraction (0.42). Accept a percentage (42) too.
    private static func percent(_ utilization: Double) -> Int {
        UsageReading.clampedPercent(utilization <= 1.5 ? utilization * 100 : utilization)
    }
}

/// One line of Claude Code's `stream-json` output (only the parts Tuloy uses).
struct StreamEvent: Decodable {
    var type: String
    var isError: Bool?
    var result: String?
    var errors: [String]?
    var rateLimits: RateLimitInfo?
    var usage: Usage?
    var modelUsage: [String: ModelUsage]?
    /// The usage check's figures (UsageOutput.swift).
    var usageReport: UsageOutput.Report?
    /// Set when Claude Code answered a slash command itself, without asking Claude.
    var localCommand: String?
    /// How many times Claude was asked. 0 for a command Claude Code answers itself.
    var numTurns: Int?
    /// The conversation's id, for carrying on with it later.
    var sessionID: String?
    /// The model, on the first line.
    var model: String?
    /// What Claude tried to do but wasn't allowed to, on the last line.
    var permissionDenials: [Denial]?

    struct Denial: Decodable {
        var tool_name: String?
    }

    /// Every line of output Tuloy can read.
    static func lines(in output: String) -> [StreamEvent] {
        output.split(whereSeparator: \.isNewline).compactMap {
            try? JSONDecoder().decode(StreamEvent.self, from: Data($0.utf8))
        }
    }

    /// Every token the run used. The per-model list is the most complete, so prefer it.
    var tokens: Int? {
        if let modelUsage, !modelUsage.isEmpty { return modelUsage.values.reduce(0) { $0 + $1.total } }
        return usage?.total
    }

    struct Usage: Decodable {
        var input_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_read_input_tokens: Int?
        var output_tokens: Int?

        var total: Int {
            (input_tokens ?? 0) + (cache_creation_input_tokens ?? 0) + (cache_read_input_tokens ?? 0) + (output_tokens ?? 0)
        }
    }

    struct ModelUsage: Decodable {
        var inputTokens: Int?
        var cacheCreationInputTokens: Int?
        var cacheReadInputTokens: Int?
        var outputTokens: Int?

        var total: Int {
            (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0) + (outputTokens ?? 0)
        }
    }

    struct RateLimitInfo: Decodable {
        var status: String?            // "allowed", "allowed_warning" or "rejected"
        var rateLimitType: String?     // "five_hour", "seven_day", ...
        var utilization: Double?       // 0...1
        var resetsAt: Double?          // Unix time
        var unifiedWindows: [String: Window]?
        var isUsingOverage: Bool?      // true if this message was paid from extra usage

        /// Every limit this report covers. Some versions list them all;
        /// others report one at a time.
        var windows: [(name: String?, window: Window)] {
            if let unifiedWindows, !unifiedWindows.isEmpty {
                return unifiedWindows.map { (name: $0.key, window: $0.value) }
            }
            return [(name: rateLimitType, window: Window(utilization: utilization, resetsAt: resetsAt))]
        }

        enum CodingKeys: String, CodingKey {
            case status, rateLimitType, utilization, resetsAt, unifiedWindows, isUsingOverage
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            status = values.optional(.status)
            rateLimitType = values.optional(.rateLimitType)
            utilization = values.optional(.utilization)
            resetsAt = values.optional(.resetsAt)
            unifiedWindows = values.optional(.unifiedWindows)
            isUsingOverage = values.optional(.isUsingOverage)
        }
    }

    struct Window: Decodable {
        var utilization: Double?
        var resetsAt: Double?
    }

    enum CodingKeys: String, CodingKey {
        case type, result, errors, usage, modelUsage
        case isError = "is_error"
        case rateLimits = "rate_limit_info"
        case usageReport = "usage_report"
        case localCommand = "local_command"
        case numTurns = "num_turns"
        case sessionID = "session_id"
        case model
        case permissionDenials = "permission_denials"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        isError = values.optional(.isError)
        result = values.optional(.result)
        errors = values.optional(.errors)
        rateLimits = type == "rate_limit_event" ? values.optional(.rateLimits) : nil
        usage = values.optional(.usage)
        modelUsage = values.optional(.modelUsage)
        usageReport = values.optional(.usageReport)
        localCommand = values.optional(.localCommand)
        numTurns = values.optional(.numTurns)
        sessionID = values.optional(.sessionID)
        model = values.optional(.model)
        permissionDenials = values.optional(.permissionDenials)
    }
}

extension KeyedDecodingContainer {
    /// A value if it's there and the type Tuloy expects, otherwise nil. Claude Code's
    /// output changes between versions, and one surprise shouldn't cost the whole line.
    func optional<T: Decodable>(_ key: Key) -> T? {
        try? decode(T.self, forKey: key)
    }
}

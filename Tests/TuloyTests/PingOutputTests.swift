import Foundation
import Testing
@testable import Tuloy

/// Claude Code's `stream-json` output, one event per line. The shapes here follow the
/// Agent SDK reference (`SDKRateLimitEvent`, `SDKResultMessage`) and real runs.
@Suite struct PingOutputTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let start = #"{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","tools":[],"mcp_servers":[]}"#
    private let reply = #"{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}"#
    private let success = #"{"type":"result","subtype":"success","is_error":false,"result":"ok","num_turns":1}"#

    /// Unix time `hours` from now.
    private func time(in hours: Double) -> Int {
        Int(now.timeIntervalSince1970 + hours * 3600)
    }

    private func rateLimit(_ info: String) -> String {
        #"{"type":"rate_limit_event","rate_limit_info":\#(info),"uuid":"u","session_id":"s"}"#
    }

    private func read(_ lines: String..., status: Int32 = 0, errors: String = "") throws -> PingReport {
        try PingOutput.read(lines.joined(separator: "\n"), status: status, errors: errors, now: now)
    }

    // MARK: - Pings that got through

    @Test func readsTheWindowResetTime() throws {
        let info = #"{"status":"allowed","resetsAt":\#(time(in: 5)),"rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}"#
        let report = try read(start, rateLimit(info), reply, success)

        #expect(report.window?.resetsAt == now.addingTimeInterval(5 * 3600))
        #expect(report.window?.percent == nil)   // Claude Code only says how much is used once you're getting close
        #expect(report.window?.asOf == now)
        #expect(report.week == nil)
        #expect(report.blockedBy == nil)
    }

    @Test func noticesAnAPIKey() {
        #expect(!PingOutput.usesAPIKey(in: #"{"type":"system","subtype":"init","apiKeySource":"none"}"#))
        #expect(PingOutput.usesAPIKey(in: #"{"type":"system","subtype":"init","apiKeySource":"ANTHROPIC_API_KEY"}"#))
        #expect(PingOutput.usesAPIKey(in: #"{"type":"system","subtype":"init","apiKeySource":"apiKeyHelper"}"#))
        #expect(!PingOutput.usesAPIKey(in: #"{"type":"system","subtype":"init"}"#))
    }

    @Test func noticesAPingPaidFromExtraUsage() throws {
        let free = #"{"status":"allowed","resetsAt":\#(time(in: 5)),"rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}"#
        #expect(try read(rateLimit(free), success).usedExtraUsage == false)
        let paid = #"{"status":"allowed","resetsAt":\#(time(in: 2)),"rateLimitType":"five_hour","overageStatus":"allowed","isUsingOverage":true}"#
        #expect(try read(rateLimit(paid), success).usedExtraUsage == true)
    }

    @Test func readsHowMuchIsUsed() throws {
        let info = #"{"status":"allowed_warning","resetsAt":\#(time(in: 2)),"rateLimitType":"five_hour","utilization":0.87}"#
        #expect(try read(rateLimit(info), success).window?.percent == 87)
    }

    @Test func readsBothLimitsWhenClaudeCodeListsThem() throws {
        let info = #"""
        {"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.23,"resetsAt":\#(time(in: 3))},"seven_day":{"utilization":0.41,"resetsAt":\#(time(in: 80))}}}
        """#
        let report = try read(rateLimit(info), success)

        #expect(report.window?.percent == 23)
        #expect(report.week?.percent == 41)
        #expect(report.week?.resetsAt == now.addingTimeInterval(80 * 3600))
    }

    @Test func tellsTheLimitsApartWhenUnnamed() throws {
        let window = try read(rateLimit(#"{"status":"allowed","resetsAt":\#(time(in: 3))}"#), success)
        #expect(window.window != nil && window.week == nil)

        let week = try read(rateLimit(#"{"status":"allowed","resetsAt":\#(time(in: 100))}"#), success)
        #expect(week.window == nil && week.week != nil)
    }

    @Test func acceptsResetTimesInMilliseconds() throws {
        let info = #"{"status":"allowed","resetsAt":\#(time(in: 4) * 1000),"rateLimitType":"five_hour"}"#
        #expect(try read(rateLimit(info), success).window?.resetsAt == now.addingTimeInterval(4 * 3600))
    }

    @Test func worksWithoutAUsageReport() throws {
        #expect(try read(start, reply, success) == PingReport())
    }

    @Test func ignoresAWindowThatHasAlreadyReset() throws {
        let info = #"{"status":"allowed","resetsAt":\#(time(in: -1)),"rateLimitType":"five_hour"}"#
        #expect(try read(rateLimit(info), success).window == nil)
    }

    @Test func ignoresLimitsItDoesNotTrack() throws {
        let info = #"{"status":"allowed","resetsAt":\#(time(in: 3)),"rateLimitType":"overage"}"#
        #expect(try read(rateLimit(info), success) == PingReport())
    }

    @Test func survivesLinesItDoesNotUnderstand() throws {
        let odd = #"{"type":"result","subtype":"success","is_error":false,"result":{"now":"an object"},"errors":42}"#
        let info = #"{"status":"allowed","resetsAt":\#(time(in: 5)),"rateLimitType":"five_hour","utilization":"lots"}"#
        let report = try read("not json at all", #"{"type":"something_new"}"#, "", rateLimit(info), odd)

        #expect(report.window?.resetsAt == now.addingTimeInterval(5 * 3600))
        #expect(report.window?.percent == nil)
    }

    // MARK: - What a ping costs

    @Test func countsTheTokensAPingUsed() throws {
        let result = #"{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":21,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":4}}"#
        #expect(try read(result).tokens == 25)
    }

    @Test func countsEveryModelTheRunUsed() throws {
        // The per-model list also covers any side requests Claude Code made, so it wins.
        let result = #"{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":21,"output_tokens":4},"modelUsage":{"claude-haiku-4-5":{"inputTokens":21,"outputTokens":4,"cacheReadInputTokens":100,"cacheCreationInputTokens":0,"costUSD":0.0001},"another-model":{"inputTokens":10,"outputTokens":5}}}"#
        #expect(try read(result).tokens == 140)
    }

    // MARK: - At a limit

    @Test func countsAPingAtTheWindowLimitAsDelivered() throws {
        // The reply fails, but the report proves a window is open and says when it resets.
        let info = #"{"status":"rejected","resetsAt":\#(time(in: 1.5)),"rateLimitType":"five_hour"}"#
        let failed = #"{"type":"result","subtype":"success","is_error":true,"result":"You've hit your session limit"}"#
        let report = try read(rateLimit(info), failed, status: 1)

        #expect(report.blockedBy == .window)
        #expect(report.window?.percent == 100)
        #expect(report.window?.resetsAt == now.addingTimeInterval(1.5 * 3600))
    }

    @Test func reportsAUsedUpWeek() throws {
        let info = #"{"status":"rejected","resetsAt":\#(time(in: 60)),"rateLimitType":"seven_day"}"#
        let failed = #"{"type":"result","subtype":"success","is_error":true,"result":"You've hit your weekly limit"}"#
        let report = try read(rateLimit(info), failed, status: 1)

        #expect(report.blockedBy == .week)
        #expect(report.window == nil)
        #expect(report.week?.percent == 100)
        #expect(report.week?.resetsAt == now.addingTimeInterval(60 * 3600))
    }

    // MARK: - Pings that failed

    @Test func recognizesAnExpiredSignIn() {
        // Seen for real: exit code 1, with the error as the "successful" result text.
        let failed = #"{"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate: OAuth session expired and could not be refreshed","terminal_reason":"api_error","num_turns":1,"total_cost_usd":0}"#
        #expect(throws: PingError.signedOut) { try read(start, failed, status: 1) }
    }

    @Test func recognizesAnOldClaudeCode() {
        #expect(throws: PingError.unknownOption) {
            try read("", status: 1, errors: "error: unknown option '--safe-mode'\n")
        }
    }

    @Test func recognizesBeingOffline() {
        let failed = #"{"type":"result","subtype":"success","is_error":true,"result":"API Error: Connection error."}"#
        #expect(throws: PingError.offline) { try read(failed, status: 1) }
    }

    @Test func passesOnOtherErrors() {
        let failed = #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Something broke\nwith details"]}"#
        #expect(throws: PingError.failed("Something broke")) { try read(failed, status: 1) }
    }

    @Test func explainsASilentFailure() {
        #expect(throws: PingError.failed("Claude Code exited with code 2.")) { try read("", status: 2) }
    }
}

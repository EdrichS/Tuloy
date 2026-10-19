import Foundation
import Testing
@testable import Tuloy

/// What `claude -p /usage --output-format stream-json --verbose` prints. The lines below are
/// trimmed from a real run of Claude Code 2.1.289 (19 October 2026): only fields Tuloy doesn't
/// read were taken out.
@Suite struct UsageOutputTests {
    let asOf = october(19, 1, 30)   // 05:30 UTC

    let start = #"{"type":"system","subtype":"init","cwd":"/Users/you/.tuloy","tools":[],"mcp_servers":[],"model":"claude-haiku-4-5-20251001","apiKeySource":"none","claude_code_version":"2.1.289"}"#

    func reply(_ limits: String, text: String = "Current session: 75% used") -> String {
        #"{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"text","text":"\#(text)"}]},"usage_report":{"session":{"total_cost_usd":0,"model_usage":{}},"rate_limits":{"limits":\#(limits),"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null}}},"local_command_run":{"command":"usage","args":""}}"#
    }

    func result(text: String = "Current session: 75% used", turns: Int = 0, tokens: Int = 0) -> String {
        #"{"type":"result","subtype":"success","is_error":false,"duration_api_ms":0,"num_turns":\#(turns),"total_cost_usd":0,"usage":{"input_tokens":\#(tokens),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"modelUsage":{},"result":"\#(text)","local_command":"usage"}"#
    }

    let realLimits = #"[{"kind":"session","group":"session","percent":75,"resets_at":"2026-10-19T05:50:00.364551+00:00","scope":null,"severity":"warning","is_active":true},{"kind":"weekly_all","group":"weekly","percent":29,"resets_at":"2026-10-22T00:00:00.364575+00:00","scope":null,"severity":"normal","is_active":false}]"#

    func read(_ lines: String..., status: Int32 = 0, errors: String = "") -> UsageOutcome {
        UsageOutput.read(lines.joined(separator: "\n"), status: status, errors: errors, asOf: asOf)
    }

    func report(_ outcome: UsageOutcome) throws -> UsageReport {
        try outcome.result.get()
    }

    @Test func readsTheRealOutput() throws {
        let outcome = read(start, reply(realLimits), result())
        let report = try report(outcome)

        #expect(outcome.wasFree)
        #expect(outcome.tokens == 0)
        #expect(outcome.version == "2.1.289")
        #expect(!outcome.usesAPIKey)
        #expect(report.window?.percent == 75)
        #expect(report.window?.resetsAt == october(19, 1, 50))   // to the whole second
        #expect(report.window?.asOf == asOf)
        #expect(report.week?.percent == 29)
        #expect(report.week?.resetsAt == october(21, 20))
        #expect(!report.noWindow)
        #expect(!report.isLastKnown)
        #expect(report.extraUsageOn == false)
    }

    @Test func noResetTimeMeansNoWindow() throws {
        let limits = #"[{"kind":"session","group":"session","percent":0,"resets_at":null},{"kind":"weekly_all","group":"weekly","percent":29,"resets_at":"2026-10-22T00:00:00+00:00"}]"#
        let report = try report(read(reply(limits), result()))
        #expect(report.window == nil)
        #expect(report.noWindow)
        #expect(report.week?.percent == 29)
    }

    @Test func aWindowThatHasEndedIsNoWindow() throws {
        let limits = #"[{"kind":"session","percent":100,"resets_at":"2026-10-19T05:20:00+00:00"}]"#
        let report = try report(read(reply(limits), result()))
        #expect(report.window == nil)
        #expect(report.noWindow)
    }

    @Test func saysNothingAboutAWindowItWasNotTold() throws {
        let limits = #"[{"kind":"weekly_all","percent":29,"resets_at":"2026-10-22T00:00:00+00:00"}]"#
        let report = try report(read(reply(limits), result()))
        #expect(report.window == nil)
        #expect(!report.noWindow)
    }

    @Test func prefersTheAllModelsWeek() throws {
        let limits = #"[{"kind":"weekly_opus","group":"weekly","percent":80,"resets_at":"2026-10-22T00:00:00+00:00"},{"kind":"weekly_all","group":"weekly","percent":29,"resets_at":"2026-10-22T00:00:00+00:00"}]"#
        #expect(try report(read(reply(limits), result())).week?.percent == 29)
    }

    @Test func survivesAnOddEntryAndOtherTimeFormats() throws {
        let limits = #"[{"kind":"something_new","percent":"lots"},{"kind":"session","percent":12.6,"resets_at":"2026-10-19T05:50:00Z"},{"kind":"weekly_all","percent":3,"resets_at":1792800000}]"#
        let report = try report(read(reply(limits), result()))
        #expect(report.window?.percent == 13)
        #expect(report.window?.resetsAt == october(19, 1, 50))
        #expect(report.week?.resetsAt == Date(timeIntervalSince1970: 1_792_800_000))
    }

    @Test func noticesLastKnownFigures() throws {
        let text = "Showing last-known usage (the usage service is busy)"
        let report = try report(read(reply(realLimits, text: text), result(text: text)))
        #expect(report.isLastKnown)
    }

    // MARK: - When it isn't free

    @Test func aCheckThatReachedClaudeIsNotFree() {
        // "/usage" sent to Claude as a message: no usage report, a real turn, real tokens.
        let outcome = read(start, #"{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","content":[{"type":"text","text":"ok"}]}}"#,
                           #"{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"ok","usage":{"input_tokens":340,"output_tokens":4},"modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":340,"outputTokens":4}}}"#)
        #expect(!outcome.wasFree)
        #expect(outcome.tokens == 344)
        #expect(throws: PingError.self) { try outcome.result.get() }
    }

    @Test func aTurnCountsEvenWithoutTokens() {
        #expect(!read(reply(realLimits), result(turns: 1)).wasFree)
    }

    // MARK: - When it fails

    @Test func signedOut() {
        let outcome = read(#"{"type":"result","subtype":"success","is_error":true,"num_turns":0,"result":"Not logged in · Please run /login"}"#, status: 1)
        #expect(outcome.wasFree)
        #expect(throws: PingError.signedOut) { try outcome.result.get() }
    }

    @Test func anOldClaudeCode() {
        let outcome = read(status: 1, errors: "error: unknown option '--safe-mode'")
        #expect(throws: PingError.unknownOption) { try outcome.result.get() }
    }

    @Test func noReportAtAll() {
        let outcome = read(start, result(text: "Unknown command: /usage"))
        #expect(outcome.wasFree)
        #expect(throws: PingError.self) { try outcome.result.get() }
    }
}

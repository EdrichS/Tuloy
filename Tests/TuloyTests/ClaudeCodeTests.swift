import Foundation
import Testing
@testable import Tuloy

@Suite struct StatusLineFileTests {
    let asOf = Date(timeIntervalSince1970: 1_738_420_000)

    private func parse(_ json: String) -> LiveUsage? {
        StatusLineFile.parse(Data(json.utf8), asOf: asOf)
    }

    @Test func readsBothLimits() {
        // The example from Claude Code's status line docs.
        let usage = parse(#"""
        {"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
        """#)

        #expect(usage?.window == UsageReading(percent: 24, resetsAt: Date(timeIntervalSince1970: 1_738_425_600), asOf: asOf))
        #expect(usage?.week == UsageReading(percent: 41, resetsAt: Date(timeIntervalSince1970: 1_738_857_600), asOf: asOf))
    }

    @Test func handlesOneLimitOnItsOwn() {
        let usage = parse(#"{"rate_limits":{"seven_day":{"used_percentage":12,"resets_at":1738857600}}}"#)
        #expect(usage?.window == nil)
        #expect(usage?.week?.percent == 12)
    }

    @Test func returnsNothingBeforeTheFirstReply() {
        // Claude Code only adds your limits once a session has had a reply.
        #expect(parse(#"{"model":{"display_name":"Opus"}}"#) == nil)
        #expect(parse(#"{"rate_limits":{}}"#) == nil)
    }

    @Test func returnsNothingForAHalfWrittenFile() {
        #expect(parse(#"{"rate_limits":{"five_hour":{"used_perc"#) == nil)
        #expect(parse("") == nil)
    }
}

@Suite struct ClaudeSetupTests {
    @Test func readyOnAClaudePlan() {
        let status = #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"you@example.com","subscriptionType":"pro"}"#
        #expect(ClaudeSetup(authStatus: status) == .ready(plan: "pro"))
        #expect(ClaudeSetup(authStatus: status).problem == nil)
    }

    @Test func signedOut() {
        #expect(ClaudeSetup(authStatus: #"{"loggedIn":false,"authMethod":"none"}"#) == .signedOut)
        #expect(ClaudeSetup.signedOut.problem == .signedOut)
    }

    @Test func usingAnAPIKeyIsNotYourPlan() {
        #expect(ClaudeSetup(authStatus: #"{"loggedIn":true,"authMethod":"api_key"}"#) == .notOnPlan)
        #expect(ClaudeSetup(authStatus: #"{"loggedIn":true,"authMethod":"third_party"}"#) == .notOnPlan)
    }

    @Test func unknownWhenClaudeCodeSaysSomethingElse() {
        #expect(ClaudeSetup(authStatus: "error: unknown command 'auth'") == .unknown)
        #expect(ClaudeSetup.unknown.problem == nil)
    }
}

@Suite struct PingErrorTests {
    @Test func everyProblemYouMustFixSaysHow() {
        for error in [PingError.claudeNotFound, .signedOut, .loginNotUsed, .notOnPlan, .unknownOption] {
            #expect(error.needsYou)
            #expect(error.recoverySuggestion != nil)
        }
        #expect(!PingError.offline.needsYou)
        #expect(!PingError.timedOut.needsYou)
    }

    @Test func keepsLongErrorsShort() {
        let error = PingError(message: String(repeating: "x", count: 500))
        #expect(error == .failed(String(repeating: "x", count: 120)))
    }
}

@Suite struct ClaudeCLITests {
    private func value(after flag: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).map { arguments[$0 + 1] }
    }

    @Test func bothPingsStayTiny() {
        for arguments in [ClaudeCLI.leanArguments, ClaudeCLI.arguments] {
            #expect(arguments.first == "-p")   // the message must come right after -p
            #expect(value(after: "--model", in: arguments) == "haiku")
            #expect(value(after: "--tools", in: arguments) == "")
            #expect(arguments.contains("--strict-mcp-config"))
            #expect(value(after: "--output-format", in: arguments) == "stream-json")
        }
    }

    @Test func theLeanPingSaysHiAndMovesTheInstructionToTheSystemPrompt() {
        #expect(ClaudeCLI.leanArguments[1] == "hi")
        #expect(value(after: "--system-prompt", in: ClaudeCLI.leanArguments) == ClaudeCLI.instruction)
        #expect(ClaudeCLI.leanArguments.contains("--safe-mode"))
        #expect(ClaudeCLI.leanArguments.contains("--no-session-persistence"))
    }

    @Test func theFallbackPingUsesOnlyOldFlags() {
        #expect(ClaudeCLI.arguments[1] == ClaudeCLI.instruction)
        #expect(!ClaudeCLI.arguments.contains("--safe-mode"))
        #expect(!ClaudeCLI.arguments.contains("--system-prompt"))
    }

    @Test func theSignInScriptRunsClaudeCodesOwnSignIn() async throws {
        let script = ClaudeCLI.signInScript(for: URL(fileURLWithPath: "/Users/you/.local/bin/claude"))
        #expect(script.hasPrefix("#!/bin/zsh\n"))
        #expect(script.contains("\n'/Users/you/.local/bin/claude' auth login\n"))

        // A path with a space and a quote must still be one argument, and the script must still parse.
        let odd = ClaudeCLI.signInScript(for: URL(fileURLWithPath: "/Users/o'neil smith/bin/claude"))
        #expect(odd.contains(#"'/Users/o'\''neil smith/bin/claude' auth login"#))
        let file = FileManager.default.temporaryDirectory.appending(path: "tuloy-sign-in-\(UUID().uuidString).command")
        defer { try? FileManager.default.removeItem(at: file) }
        try odd.write(to: file, atomically: true, encoding: .utf8)
        let check = try await Shell.run(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-n", file.path(percentEncoded: false)], timeout: 10)
        #expect(check.status == 0)   // zsh -n reads the script without running it
    }

    @Test func pingsAlwaysUseYourPlanWithThinkingOff() {
        let inherited = ["ANTHROPIC_API_KEY": "sk-test", "CLAUDE_CODE_SIMPLE": "1", "CLAUDE_CODE_USE_BEDROCK": "1",
                         "PATH": "/usr/bin", "HOME": "/Users/you"]
        let env = ClaudeCLI.environment(for: URL(fileURLWithPath: "/opt/tools/claude"), from: inherited)

        #expect(env["ANTHROPIC_API_KEY"] == nil)         // never API billing
        #expect(env["CLAUDE_CODE_USE_BEDROCK"] == nil)   // never another provider
        #expect(env["CLAUDE_CODE_SIMPLE"] == nil)        // never bare mode, which skips your login
        #expect(env["MAX_THINKING_TOKENS"] == "0")
        #expect(env["HOME"] == "/Users/you")
        #expect(env["PATH"]?.hasPrefix("/opt/tools:") == true)
        #expect(env["PATH"]?.hasSuffix(":/usr/bin") == true)
    }
}

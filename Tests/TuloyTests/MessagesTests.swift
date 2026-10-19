import Foundation
import Testing
@testable import Tuloy

/// Your scheduled messages: when they go, what they may do, and that they never cost money.
@MainActor
@Suite struct MessagesTests {

    private func message(_ when: ScheduledMessage.When, title: String = "Morning summary") -> ScheduledMessage {
        var message = ScheduledMessage()
        message.title = title
        message.prompt = "Summarise yesterday's commits."
        message.when = when
        return message
    }

    /// Lets the message that's being sent finish.
    private func finish(_ world: World) async {
        await world.engine.messageTask?.value
    }

    // MARK: - When they go

    @Test func aOneOffGoesAtItsTimeThenSwitchesOff() async {
        let world = World()
        world.engine.save(message(.once(october(5, 9))))
        await world.run(until: october(5, 8, 59))
        #expect(world.claude.messagesSent.isEmpty)

        await world.run(until: october(5, 9, 1))
        await finish(world)
        #expect(world.claude.messagesSent.count == 1)
        #expect(world.engine.messages[0].isOn == false)
        #expect(world.engine.messageRuns.first?.outcome == .done)
        #expect(world.engine.messageRuns.first?.text == "Done.")
        #expect(world.engine.messageRuns.first?.sessionID == "session-1")

        await world.run(until: october(5, 12))
        await finish(world)
        #expect(world.claude.messagesSent.count == 1)   // once means once
    }

    @Test func aDailyOneGoesOnItsDaysOnly() async {
        let world = World()
        // Weekdays only, at 9:00 AM. 5 October 2026 is a Monday.
        world.engine.save(message(.daily(minutes: 9 * 60, weekdays: [2, 3, 4, 5, 6])))
        for day in 5...11 {
            await world.go(to: october(day, 9, 0, 30))
            await finish(world)
        }
        let days = world.claude.messagesSent.map { calendar.component(.day, from: $0.at) }
        #expect(days == [5, 6, 7, 8, 9])   // not Saturday the 10th or Sunday the 11th
        #expect(world.engine.messages[0].nextRun == october(12, 9))
    }

    @Test func atTheNextFreshWindowFollowsTheWindow() async {
        let world = World()   // 4:00 AM; the 6:00 ping will give a fresh window at 11:00
        world.engine.save(message(.nextFreshWindow))
        #expect(world.engine.messages[0].nextRun == october(5, 11, 1))

        await world.run(until: october(5, 11, 0, 30))
        #expect(world.claude.messagesSent.isEmpty)
        await world.run(until: october(5, 11, 2))
        await finish(world)
        #expect(world.claude.messagesSent.count == 1)
        #expect(world.claude.messagesSent[0].at >= october(5, 11, 1))
    }

    @Test func aFreshWindowMessageWaitsForAPlanIfThereIsNone() async {
        let world = World(["weekdays": [Int]()])   // no days chosen: no fresh window planned
        world.engine.save(message(.nextFreshWindow))
        #expect(world.engine.messages[0].nextRun == nil)

        // You start a window by hand. Its end is the next fresh window.
        await world.engine.pingNow()
        await world.engine.tick()
        #expect(world.engine.messages[0].nextRun == october(5, 9, 1))
        #expect(world.notices.permissionAsked)
    }

    @Test func aMessageDoesNotHoldUpThePings() async {
        let world = World()
        world.claude.messagesTake(.milliseconds(300))
        world.engine.save(message(.once(october(5, 6))))
        await world.go(to: october(5, 6, 0, 15))   // the message and the scheduled ping are both due
        #expect(world.claude.pings == 1)   // the ping went while the message was still being worked on
        #expect(world.engine.sendingMessage != nil)
        await finish(world)
        #expect(world.engine.sendingMessage == nil)
    }

    @Test func oneAtATime() async {
        let world = World()
        world.claude.messagesTake(.milliseconds(200))
        world.engine.save(message(.once(october(5, 9)), title: "First"))
        world.engine.save(message(.once(october(5, 9)), title: "Second"))
        await world.go(to: october(5, 9, 0, 10))
        #expect(world.engine.sendingMessage != nil)
        await world.go(to: october(5, 9, 0, 20))   // the first is still going: the second waits
        await finish(world)
        #expect(world.claude.messagesSent.count == 1)
        await world.go(to: october(5, 9, 0, 40))
        await finish(world)
        #expect(world.claude.messagesSent.map(\.message.title) == ["First", "Second"])
    }

    // MARK: - A sleeping Mac

    @Test func aLittleLateAfterSleepStillGoes() async {
        let world = World()
        world.engine.save(message(.once(october(5, 9))))
        await world.run(until: october(5, 8, 50))
        await world.go(to: october(5, 10, 30))   // asleep from 8:50 to 10:30
        await finish(world)
        #expect(world.claude.messagesSent.count == 1)
        #expect(world.engine.messageRuns.first?.late?.reason == .asleep)
    }

    @Test func tooLateIsMissedNotSent() async {
        let world = World()
        world.engine.save(message(.daily(minutes: 9 * 60, weekdays: Array(1...7))))
        await world.run(until: october(5, 8, 50))
        await world.go(to: october(5, 13))   // asleep past 9:00 by four hours
        await finish(world)
        #expect(world.claude.messagesSent.isEmpty)
        #expect(world.engine.messageRuns.first?.outcome == .notSent)
        #expect(world.engine.messageRuns.first?.text.hasPrefix("Missed: your Mac was asleep at") == true)
        #expect(world.engine.messages[0].nextRun == october(6, 9))   // tomorrow's still on
    }

    @Test func youCanSayNotToSendLate() async {
        let world = World()
        var late = message(.once(october(5, 9)))
        late.sendsLate = false
        world.engine.save(late)
        await world.run(until: october(5, 8, 50))
        await world.go(to: october(5, 9, 20))
        await finish(world)
        #expect(world.claude.messagesSent.isEmpty)
        #expect(world.engine.messageRuns.first?.text.contains("as you asked") == true)
    }

    // MARK: - Never paid for

    @Test func notSentWhileClaudeCodeHasAnAPIKey() async {
        let world = World()
        var keyed = world.usage()
        keyed.usesAPIKey = true
        world.claude.usageAlways(keyed)
        await world.engine.tick()
        world.engine.save(message(.once(october(5, 4, 10))))
        await world.run(until: october(5, 4, 12))
        await finish(world)
        #expect(world.claude.messagesSent.isEmpty)
        #expect(world.engine.messageRuns.first?.outcome == .notSent)
        #expect(world.engine.messageRuns.first?.text.contains("billed") == true)
    }

    @Test func notSentWhileTheWeekIsUsedUp() async {
        let world = World()
        world.claude.nextUsage(world.usage(week: world.reading(100, resets: october(7, 20))))
        await world.engine.tick()
        let saved = message(.once(october(5, 4, 10)))
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        await finish(world)
        #expect(world.claude.messagesSent.isEmpty)
        #expect(world.engine.notice?.text.hasPrefix("Not sent: your weekly limit is used up") == true)
    }

    @Test func aMessageThatReportsAnAPIKeyStopsEverything() async {
        let world = World()
        var outcome = MessageOutcome(result: .success("Hello"), version: "2.1.288")
        outcome.usedAPIKey = true
        world.claude.nextMessage(outcome)
        let saved = message(.once(october(5, 9)))
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        await finish(world)
        #expect(world.engine.apiKeyInUse)
        await world.engine.pingNow()
        #expect(world.claude.pings == 0)
    }

    // MARK: - Windows

    @Test func aMessageThatOpensAWindowAtPingTimeDoesThePingsJob() async {
        let world = World()
        world.engine.save(message(.once(october(5, 6))))
        world.clock.now = october(5, 6, 0, 5)   // ten seconds before the scheduled ping
        world.claude.nextMessage(MessageOutcome(result: .success("Done."), report: world.claude.freshWindow(percent: 4), version: "2.1.288"))
        await world.engine.tick()
        await finish(world)
        #expect(world.engine.messageRuns.first?.openedWindow == true)
        #expect(world.engine.messageRuns.first?.windowResets == october(5, 11))
        #expect(world.engine.nextPingAt == october(6, 6, 0, 15))   // the 6:00 ping wasn't needed

        await world.run(until: october(5, 7))
        #expect(world.claude.pings == 0)
    }

    @Test func aMessageInAnOpenWindowOpensNothing() async {
        let world = World()
        await world.go(to: october(5, 6, 0, 15))   // the ping opens 6:00 to 11:00
        world.engine.save(message(.once(october(5, 8))))
        world.clock.now = october(5, 8, 0, 10)
        let report = PingReport(window: world.reading(30, resets: october(5, 11)), tokens: 1200)
        world.claude.nextMessage(MessageOutcome(result: .success("Done."), report: report, version: "2.1.288"))
        await world.engine.tick()
        await finish(world)
        #expect(world.engine.messageRuns.first?.openedWindow == false)
        #expect(world.engine.usagePercent == 30)
    }

    // MARK: - Stopping, and what's kept

    @Test func stopEndsIt() async {
        let world = World()
        world.claude.messagesTake(.seconds(5))
        let saved = message(.once(october(5, 9)))
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        try? await Task.sleep(for: .milliseconds(50))
        world.engine.stopSending()
        await finish(world)
        #expect(world.engine.messageRuns.first?.outcome == .stopped)
        #expect(world.engine.messageRuns.first?.text == "Stopped by you.")
        #expect(world.engine.messages[0].isOn)   // its own time still stands
    }

    @Test func aFailureSaysWhy() async {
        let world = World()
        world.claude.nextMessage(MessageOutcome(result: .failure(.signedOut), version: "2.1.288"))
        let saved = message(.once(october(5, 9)))
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        await finish(world)
        #expect(world.engine.messageRuns.first?.outcome == .failed)
        #expect(world.engine.messageRuns.first?.text.hasPrefix("Claude Code needs its own sign-in.") == true)
        #expect(world.notices.count("message-\(saved.id.uuidString)") == 1)
    }

    @Test func whatClaudeWasNotAllowedToDoIsKept() async {
        let world = World()
        world.claude.nextMessage(MessageOutcome(result: .success("I couldn't edit the file."), version: "2.1.288", refused: ["Edit", "Bash"]))
        let saved = message(.once(october(5, 9)))
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        await finish(world)
        #expect(world.engine.messageRuns.first?.refused == ["Edit", "Bash"])
    }

    @Test func aConversationNotKeptHasNoWayBack() async {
        let world = World()
        var saved = message(.once(october(5, 9)))
        saved.keepsConversation = false
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        await finish(world)
        #expect(world.engine.messageRuns.first?.sessionID == nil)
    }

    @Test func messagesAndRunsSurviveARestart() async {
        let world = World()
        let saved = message(.daily(minutes: 9 * 60, weekdays: Array(1...7)))
        world.engine.save(saved)
        world.engine.sendNow(saved.id)
        await finish(world)
        let again = world.restarted()
        #expect(again.messages.map(\.id) == [saved.id])
        #expect(again.messageRuns.count == 1)
        #expect(again.messages[0].nextRun == october(5, 9))
    }
}

/// The command each message becomes.
@Suite struct MessageCommandTests {

    private func arguments(_ change: (inout ScheduledMessage) -> Void) -> [String] {
        var message = ScheduledMessage()
        message.title = "Tidy"
        message.prompt = "-- a message that starts with dashes"
        change(&message)
        return ClaudeCLI.messageArguments(for: message)
    }

    @Test func theMessageItselfIsNeverAnArgument() {
        let args = arguments { _ in }
        #expect(!args.contains { $0.contains("dashes") })
        #expect(args.starts(with: ["-p", "--output-format", "stream-json", "--verbose"]))
    }

    @Test func answerOnlyHasNoTools() {
        let args = arguments { $0.access = .answerOnly }
        #expect(args.contains(["--tools", ""]))
        #expect(args.contains(["--permission-prompts", "none"]))
        #expect(!args.contains("--dangerously-skip-permissions"))
    }

    @Test func readingCanOnlyRead() {
        let args = arguments { $0.access = .read }
        #expect(args.contains(["--tools", "Read,Grep,Glob"]))
        #expect(!args.contains("--permission-mode"))
    }

    @Test func editingCanEditButRunsNothing() {
        let args = arguments { $0.access = .edit }
        #expect(args.contains(["--tools", "Read,Grep,Glob,Edit,Write"]))
        #expect(args.contains(["--permission-mode", "acceptEdits"]))
        #expect(!args.contains { $0.contains("Bash") })
    }

    @Test func fullAccessSkipsTheQuestions() {
        let args = arguments { $0.access = .full }
        #expect(args.contains("--dangerously-skip-permissions"))
        #expect(!args.contains("--tools"))
    }

    @Test func theWebIsExtra() {
        let args = arguments { $0.access = .read; $0.canUseWeb = true }
        #expect(args.contains(["--tools", "Read,Grep,Glob,WebSearch,WebFetch"]))
        #expect(args.contains(["--allowedTools", "WebSearch,WebFetch"]))
    }

    @Test func modelEffortAndTheRest() {
        let args = arguments {
            $0.model = "opus"
            $0.effort = "high"
            $0.usesYourSetup = false
            $0.instructions = "Answer in Tagalog."
            $0.keepsConversation = false
        }
        #expect(args.contains(["--model", "opus"]))
        #expect(args.contains(["--effort", "high"]))
        #expect(args.contains(["--safe-mode", "--strict-mcp-config"]))
        #expect(args.contains(["--append-system-prompt", "Answer in Tagalog."]))
        #expect(args.contains("--no-session-persistence"))
        #expect(!args.contains("--name"))
    }

    @Test func claudeCodesDefaultsAreLeftAlone() {
        let args = arguments { _ in }
        #expect(!args.contains("--model"))
        #expect(!args.contains("--effort"))
        #expect(args.contains(["--name", "Tuloy: Tidy"]))
    }

    @Test func aMessageIsNotShrunkLikeAPing() {
        let env = ClaudeCLI.environment(for: URL(fileURLWithPath: "/usr/local/bin/claude"), forPing: false,
                                        from: ["ANTHROPIC_API_KEY": "sk-test", "PATH": "/usr/bin"])
        #expect(env["MAX_THINKING_TOKENS"] == nil)   // your effort setting decides the thinking
        #expect(env["ANTHROPIC_API_KEY"] == nil)     // and it's never billed to a key
    }
}

/// What Claude Code prints after a message.
@Suite struct MessageOutputTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func readsTheReplyAndTheRest() {
        let output = [
            #"{"type":"system","subtype":"init","session_id":"abc-123","model":"claude-sonnet-4-5","apiKeySource":"none","claude_code_version":"2.1.289"}"#,
            #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour","resetsAt":\#(Int(now.timeIntervalSince1970) + 7200),"utilization":0.31}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"num_turns":4,"result":"Three commits yesterday.","session_id":"abc-123","usage":{"input_tokens":5000,"output_tokens":800},"permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{}}]}"#,
        ].joined(separator: "\n")
        let outcome = MessageOutput.read(output, now: now)

        #expect((try? outcome.result.get()) == "Three commits yesterday.")
        #expect(outcome.sessionID == "abc-123")
        #expect(outcome.model == "claude-sonnet-4-5")
        #expect(outcome.version == "2.1.289")
        #expect(outcome.report.tokens == 5800)
        #expect(outcome.report.window?.percent == 31)
        #expect(outcome.refused == ["Bash"])
        #expect(!outcome.usedAPIKey)
    }

    @Test func readsAFailure() {
        let output = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Not logged in · Please run /login"}"#
        let outcome = MessageOutput.read(output, status: 1, now: now)
        #expect(throws: PingError.signedOut) { try outcome.result.get() }
    }

    @Test func readsAModelYourPlanDoesNotHave() {
        let output = #"{"type":"result","is_error":true,"result":"Model claude-fable is not available on your plan."}"#
        let outcome = MessageOutput.read(output, status: 1, now: now)
        #expect(throws: PingError.failed("Model claude-fable is not available on your plan.")) { try outcome.result.get() }
    }
}

import Foundation

/// Pings Claude through the Claude Code CLI you're already signed in to.
///
/// Tuloy never touches your login or tokens. Claude Code does the talking,
/// so the ping counts toward your plan's 5-hour window, not API billing.
enum ClaudeCLI {
    /// Keeps the reply to one word. A bare "hi" would cost more: the answer
    /// would be a whole greeting, and words Claude writes count the most.
    static let instruction = "Reply with only the word ok."

    /// The smallest ping: the smallest model, no tools, no MCP servers, none of your hooks,
    /// plugins or CLAUDE.md, and no saved transcript. The one-line instruction replaces Claude
    /// Code's long built-in one, so the message itself can be just "hi".
    /// `stream-json` includes Claude Code's usage report (percent used and reset time).
    /// The message must stay right after `-p`, before the list-style flags.
    static let leanArguments = [
        "-p", "hi",
        "--system-prompt", instruction,
        "--model", "haiku",
        "--tools", "",
        "--strict-mcp-config",
        "--safe-mode",
        "--no-session-persistence",
        "--output-format", "stream-json", "--verbose",
    ]

    /// The same ping using only flags every Claude Code version knows.
    static let arguments = [
        "-p", instruction,
        "--model", "haiku",
        "--tools", "",
        "--strict-mcp-config",
        "--output-format", "stream-json", "--verbose",
    ]

    /// The free usage check: Claude Code's own `/usage`, answered on this Mac without asking
    /// Claude, so it uses no tokens and starts no window. The other flags keep it quick (no MCP
    /// servers, none of your hooks) and leave no saved transcript behind. If "/usage" ever reached
    /// Claude as a message, they'd also keep it as small as a ping; Tuloy would notice and stop.
    static let usageArguments = [
        "-p", "/usage",
        "--model", "haiku",
        "--tools", "",
        "--strict-mcp-config",
        "--safe-mode",
        "--no-session-persistence",
        "--output-format", "stream-json", "--verbose",
    ]

    /// For a Claude Code that doesn't know `--safe-mode`. Everything else stays, so a check
    /// can never cost more than a ping.
    static let plainUsageArguments = [
        "-p", "/usage",
        "--model", "haiku",
        "--tools", "",
        "--strict-mcp-config",
        "--no-session-persistence",
        "--output-format", "stream-json", "--verbose",
    ]

    /// Sends one ping, starting with whichever command last worked.
    static func ping(remembering memory: PingMemory?) async -> PingOutcome {
        guard let claude = await locator.find() else {
            return PingOutcome(result: .failure(.claudeNotFound), style: memory?.style ?? .lean)
        }

        let first = memory?.style ?? .lean
        var outcome = await run(first, with: claude)
        if outcome.usedAPIKey {
            // Claude Code used an API key from its own settings, not your plan: that ping was billed.
            // No second try, and none after until that's fixed.
            outcome.result = .failure(.notOnPlan)
            return outcome
        }
        if first == .lean, case .failure(let error) = outcome.result,
           PingMemory.mayFallBack(after: error, memory: memory, version: outcome.version) {
            // Perhaps a Claude Code that doesn't know the newer flags. The plain command works on any.
            let plain = await run(.plain, with: claude)
            outcome = PingOutcome(result: plain.result, style: .plain, version: plain.version ?? outcome.version,
                                  usedAPIKey: plain.usedAPIKey)
            if outcome.usedAPIKey {
                outcome.result = .failure(.notOnPlan)
                return outcome
            }
        }

        if case .failure(.signedOut) = outcome.result, case .ready = await checkSetup() {
            // Claude Code says you're signed in, yet the ping couldn't use your login. Say so:
            // "sign in" alone would be the wrong advice if Claude Code changed how pings sign in.
            outcome.result = .failure(.loginNotUsed)
        }
        return outcome
    }

    private static func run(_ style: PingStyle, with claude: URL) async -> PingOutcome {
        do {
            let run = try await Shell.run(claude, arguments: style == .lean ? leanArguments : arguments,
                                          environment: environment(for: claude), directory: Paths.tuloy, timeout: 90)
            let version = PingOutput.version(in: run.output)
            let usedAPIKey = PingOutput.usesAPIKey(in: run.output)
            do {
                let report = try PingOutput.read(run.output, status: run.status, errors: run.errors)
                return PingOutcome(result: .success(report), style: style, version: version, usedAPIKey: usedAPIKey)
            } catch {
                return PingOutcome(result: .failure(error as? PingError ?? .failed(error.localizedDescription)), style: style,
                                   version: version, usedAPIKey: usedAPIKey)
            }
        } catch {
            return PingOutcome(result: .failure(error as? PingError ?? .failed(error.localizedDescription)), style: style)
        }
    }

    /// Reads your usage, free. Falls back to the plain command only if the first one used a flag
    /// this Claude Code doesn't know.
    static func checkUsage() async -> UsageOutcome {
        guard let claude = await locator.find() else { return UsageOutcome(result: .failure(.claudeNotFound)) }
        let outcome = await runUsage(usageArguments, with: claude)
        if case .failure(.unknownOption) = outcome.result {
            return await runUsage(plainUsageArguments, with: claude)
        }
        return outcome
    }

    private static func runUsage(_ arguments: [String], with claude: URL) async -> UsageOutcome {
        let startedAt = Date()
        do {
            let run = try await Shell.run(claude, arguments: arguments, environment: environment(for: claude),
                                          directory: Paths.tuloy, timeout: 30)
            return UsageOutput.read(run.output, status: run.status, errors: run.errors, asOf: startedAt)
        } catch {
            return UsageOutcome(result: .failure(error as? PingError ?? .failed(error.localizedDescription)))
        }
    }

    // MARK: - Your scheduled messages

    /// The command for one of your messages. The message itself goes in on standard input, so a
    /// message of any length, or one starting with "-", can't be mistaken for an option.
    static func messageArguments(for message: ScheduledMessage) -> [String] {
        var arguments = ["-p", "--output-format", "stream-json", "--verbose"]
        if !message.model.isEmpty { arguments += ["--model", message.model] }
        if !message.effort.isEmpty { arguments += ["--effort", message.effort] }

        // What Claude may do. Nobody is there to approve anything, so whatever needs approval is refused.
        var tools: [String]?
        switch message.access {
        case .answerOnly:
            tools = []
        case .read:
            tools = ["Read", "Grep", "Glob"]
        case .edit:
            tools = ["Read", "Grep", "Glob", "Edit", "Write"]
            arguments += ["--permission-mode", "acceptEdits"]   // edits inside the folder, and only there
        case .full:
            arguments += ["--dangerously-skip-permissions"]
        }
        if message.canUseWeb, tools != nil {
            tools? += ["WebSearch", "WebFetch"]
            arguments += ["--allowedTools", "WebSearch,WebFetch"]
        }
        if let tools { arguments += ["--tools", tools.joined(separator: ",")] }
        arguments += ["--permission-prompts", "none"]

        if !message.usesYourSetup { arguments += ["--safe-mode", "--strict-mcp-config"] }
        if !message.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--append-system-prompt", message.instructions]
        }
        // Kept conversations get a name, so they're easy to find in Claude Code's list.
        arguments += message.keepsConversation ? ["--name", "Tuloy: \(message.name)"] : ["--no-session-persistence"]
        return arguments
    }

    /// Sends one of your messages and waits for Claude to finish with it.
    static func send(_ message: ScheduledMessage) async -> MessageOutcome {
        guard let claude = await locator.find() else { return MessageOutcome(result: .failure(.claudeNotFound)) }
        let folder = message.folderURL ?? Paths.tuloy
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isFolder), isFolder.boolValue else {
            return MessageOutcome(result: .failure(.failed("The folder \(message.folder) isn't there any more.")))
        }
        do {
            let run = try await Shell.run(claude, arguments: messageArguments(for: message),
                                          environment: environment(for: claude, forPing: false), directory: folder,
                                          input: Data(message.prompt.utf8), timeout: TimeInterval(max(1, message.minutesAllowed) * 60))
            return MessageOutput.read(run.output, status: run.status, errors: run.errors)
        } catch {
            return MessageOutcome(result: .failure(error as? PingError ?? .failed("Stopped.")))
        }
    }

    /// Checks that Claude Code is installed and signed in, without sending a message.
    static func checkSetup() async -> ClaudeSetup {
        guard let claude = await locator.find() else { return .notInstalled }
        guard let run = try? await Shell.run(claude, arguments: ["auth", "status"], environment: environment(for: claude),
                                             directory: Paths.tuloy, timeout: 20)
        else { return .unknown }
        return ClaudeSetup(authStatus: run.output)
    }

    /// Claude Code's version, such as "2.1.288". Instant, and sends nothing.
    static func version() async -> String? {
        guard let claude = await locator.find(),
              let run = try? await Shell.run(claude, arguments: ["--version"], environment: environment(for: claude), timeout: 10)
        else { return nil }
        return run.output.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// What Terminal runs when you choose Sign In: Claude Code's own sign-in, and nothing else.
    /// When it finishes it leaves `marker` behind, which is how Tuloy knows to look again at once.
    static func signInScript(for claude: URL, marker: URL) -> String {
        let quoted = { (url: URL) in shellQuoted(url.path(percentEncoded: false)) }
        return """
        #!/bin/zsh
        # Made by Tuloy. Signs Claude Code in with your Claude account, in your browser.
        clear
        echo "Signing in to Claude Code for Tuloy."
        echo "Your browser will open. Sign in with the account that has your Claude plan."
        echo
        \(quoted(claude)) auth login
        touch \(quoted(marker))
        echo
        echo "Done. You can close this window and go back to Tuloy."

        """
    }

    /// Single quotes keep text with spaces in one piece. A quote inside is closed, escaped and reopened.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// What Terminal runs for "Continue in Terminal": the conversation one of your messages had, in its folder.
    static func continueScript(for claude: URL, session: String, folder: URL) -> String {
        """
        #!/bin/zsh
        # Made by Tuloy. Carries on a conversation from one of your scheduled messages.
        cd \(shellQuoted(folder.path(percentEncoded: false))) || exit 1
        clear
        \(shellQuoted(claude.path(percentEncoded: false))) --resume \(shellQuoted(session))

        """
    }

    /// Where the `claude` command is. Found once and remembered, even between launches.
    static let locator = Locator(
        remembered: UserDefaults.standard.string(forKey: "claudeFoundAt"),
        search: { await searchForClaude() },
        found: { UserDefaults.standard.set($0?.path(percentEncoded: false), forKey: "claudeFoundAt") }
    )

    /// Looks for the `claude` command, checking the usual install spots first.
    private static func searchForClaude() async -> URL? {
        let home = NSHomeDirectory()
        let usualPlaces = [
            "\(home)/.local/bin/claude",       // Claude Code's native installer
            "\(home)/.claude/local/claude",    // older local installs
            "/opt/homebrew/bin/claude",        // Homebrew on Apple silicon
            "/usr/local/bin/claude",           // Homebrew on Intel, and npm
        ]
        if let path = usualPlaces.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        // Somewhere else: ask your login shell.
        let shell = try? await Shell.run(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "command -v claude"], timeout: 10)
        let path = (shell?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// What `claude` runs with: Tuloy's own environment, adjusted so it uses your plan, and for a
    /// ping (not one of your messages) so it's as small as it gets.
    static func environment(for claude: URL, forPing: Bool = true,
                            from base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        // Always use your Claude login, never API billing or another provider.
        // (CLAUDE_CODE_SIMPLE is "bare mode", which skips your login.)
        for name in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
                     "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_SIMPLE"] {
            env[name] = nil
        }
        if forPing {
            // No thinking before the one-word reply. (Haiku has no effort levels, so this is its lowest setting.)
            env["MAX_THINKING_TOKENS"] = "0"
            // If the ping falls back to Claude Code's built-in instructions, ask for the short version.
            env["CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT"] = "1"
        }
        // Apps don't get your shell's PATH. Add claude's folder (npm installs keep node there too).
        let folders = [(claude.path(percentEncoded: false) as NSString).deletingLastPathComponent,
                       "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"]
        env["PATH"] = folders.joined(separator: ":")
        return env
    }
}

/// Remembers where the `claude` command is, so the search runs once and not before every ping.
/// Before each use it makes one cheap check that the file is still there, and searches again if not.
final class Locator: @unchecked Sendable {
    private let lock = NSLock()
    private var known: URL?
    private let isRunnable: @Sendable (String) -> Bool
    private let search: @Sendable () async -> URL?
    private let found: @Sendable (URL?) -> Void

    init(remembered: String? = nil,
         isRunnable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
         search: @escaping @Sendable () async -> URL?,
         found: @escaping @Sendable (URL?) -> Void = { _ in }) {
        known = remembered.map { URL(fileURLWithPath: $0) }
        self.isRunnable = isRunnable
        self.search = search
        self.found = found
    }

    func find() async -> URL? {
        let remembered = lock.withLock { known }
        if let remembered, isRunnable(remembered.path(percentEncoded: false)) { return remembered }

        let result = await search()
        lock.withLock { known = result }
        found(result)
        return result
    }
}

/// The real Claude Code: runs the `claude` command on this Mac.
struct RealClaude: ClaudeCode {
    func ping(remembering memory: PingMemory?) async -> PingOutcome {
        await ClaudeCLI.ping(remembering: memory)
    }

    func checkSetup() async -> ClaudeSetup {
        await ClaudeCLI.checkSetup()
    }

    func checkUsage() async -> UsageOutcome {
        await ClaudeCLI.checkUsage()
    }

    func send(_ message: ScheduledMessage) async -> MessageOutcome {
        await ClaudeCLI.send(message)
    }

    func locate() async -> String? {
        await ClaudeCLI.locator.find().map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }
    }

    func version() async -> String? {
        await ClaudeCLI.version()
    }
}

/// What to do after a ping fails.
enum RetryRule: Sendable {
    /// No retry can work. Wait until the free check says you've fixed it.
    case whenYouFixIt
    /// Once more at the next scheduled time, not before.
    case atNextSchedule
    /// After 1, 2, 5, 15, then 30 minutes.
    case soon
    /// The same, but after five tries only once an hour.
    case soonThenHourly
}

/// Why a ping didn't get through.
enum PingError: LocalizedError, Equatable, Sendable {
    case claudeNotFound
    case signedOut
    /// Claude Code says you're signed in, but the ping couldn't use that login. Either the login
    /// has gone stale, or a Claude Code update changed how `claude -p` signs in (see HOW_IT_WORKS.md).
    case loginNotUsed
    /// Claude Code is set up with an API key or another provider instead of your Claude plan.
    case notOnPlan
    case offline
    case timedOut
    /// This Claude Code is too old for one of the flags Tuloy passed.
    case unknownOption
    case failed(String)

    /// Sorts Claude Code's own error text into the cases Tuloy can explain.
    init(message: String) {
        let text = message.lowercased()
        let mentions = { (words: [String]) in words.contains(where: text.contains) }

        if mentions(["unknown option"]) {
            self = .unknownOption
        } else if mentions(["authenticate", "oauth", "/login", "not logged in", "invalid api key"]) {
            self = .signedOut
        } else if mentions(["connection error", "network", "enotfound", "econnrefused", "fetch failed"]) {
            self = .offline
        } else {
            let firstLine = message.split(whereSeparator: \.isNewline).first.map { String($0.prefix(120)) }
            self = .failed(firstLine ?? message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .claudeNotFound: return "Can't find Claude Code."
        case .signedOut: return "Claude Code needs its own sign-in."
        case .loginNotUsed: return "The ping couldn't use your Claude login."
        case .notOnPlan: return "Claude Code isn't using your Claude plan."
        case .offline: return "Couldn't reach Claude."
        case .timedOut: return "Claude Code didn't answer in time."
        case .unknownOption: return "This version of Claude Code is too old."
        case .failed(let message): return message
        }
    }

    /// What to do about it.
    var recoverySuggestion: String? {
        switch self {
        case .claudeNotFound: return "Tuloy pings through Claude Code. Open Connection for how to install it."
        case .signedOut: return "Being signed in to the Claude app or claude.ai isn't enough. Open Connection and choose Sign In."
        case .loginNotUsed: return "Open Connection and sign in again. If it keeps happening, look for a Tuloy update."
        case .notOnPlan: return "Run \"claude\" in Terminal and sign in with your Claude account, not an API key."
        case .offline: return "Check your internet connection. Tuloy will try again."
        case .timedOut: return "Tuloy will try again."
        case .unknownOption: return "Run \"claude update\" in Terminal. Tuloy notices when it's done."
        case .failed: return nil
        }
    }

    /// True when the cause is unclear enough that the newer, optional flags could be to blame.
    var mayBeTheExtras: Bool {
        switch self {
        case .unknownOption, .signedOut, .failed: return true
        case .claudeNotFound, .loginNotUsed, .notOnPlan, .offline, .timedOut: return false
        }
    }

    /// What to do after this failure: try again soon, or wait for you.
    var retry: RetryRule {
        switch self {
        case .claudeNotFound, .signedOut, .notOnPlan, .unknownOption: return .whenYouFixIt
        case .loginNotUsed: return .atNextSchedule
        case .offline, .timedOut: return .soon
        case .failed: return .soonThenHourly
        }
    }

    /// True when it won't fix itself: you need to do something.
    var needsYou: Bool {
        switch self {
        case .claudeNotFound, .signedOut, .loginNotUsed, .notOnPlan, .unknownOption: return true
        case .offline, .timedOut, .failed: return false
        }
    }
}

/// Whether Claude Code is ready for Tuloy to use.
enum ClaudeSetup: Equatable, Sendable {
    case checking
    /// Signed in with a Claude plan ("pro", "max", ...), if Claude Code said which.
    case ready(plan: String?)
    case notInstalled
    case signedOut
    case notOnPlan
    /// Claude Code didn't say. Tuloy will find out at the next ping.
    case unknown

    /// Reads the JSON printed by `claude auth status`.
    init(authStatus json: String) {
        struct Status: Decodable {
            var loggedIn: Bool?
            var authMethod: String?
            var subscriptionType: String?
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: Data(json.utf8)) else {
            self = .unknown
            return
        }

        if status.loggedIn == false || status.authMethod == "none" {
            self = .signedOut
        } else if let method = status.authMethod, ["api_key", "api_key_helper", "third_party"].contains(method) {
            self = .notOnPlan
        } else {
            self = .ready(plan: status.subscriptionType)
        }
    }

    /// The problem to show, if Claude Code isn't ready.
    var problem: PingError? {
        switch self {
        case .notInstalled: return .claudeNotFound
        case .signedOut: return .signedOut
        case .notOnPlan: return .notOnPlan
        case .checking, .ready, .unknown: return nil
        }
    }

    var plan: String? {
        if case .ready(let plan) = self { return plan }
        return nil
    }
}

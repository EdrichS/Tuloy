import AppKit
import SwiftUI

/// The Connection screen: everything Tuloy needs from Claude Code, checked one step at a time.
struct ConnectionContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connection")
                    .font(.title2.weight(.semibold))
                Text(Commands.surprise)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tuloy sends its pings through Claude Code, Anthropic's command-line app. It has to be installed and signed in on this Mac. Work down the steps: each one shows whether it's done.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open the Step-by-Step Guide") { model.open(.guide) }
                .buttonStyle(TuloyButtonStyle())

            ConnectionChecklist(model: model)
        }
    }
}

/// The steps themselves. Also used by the welcome window.
struct ConnectionChecklist: View {
    let model: AppModel
    /// The welcome window leaves the optional last step for later.
    var showsLiveUsage = true

    @State private var testedAt: Date?
    @State private var couldNotOpenTerminal = false
    @State private var isConfirmingLiveUsage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            installStep
            signInStep
            testStep
            if showsLiveUsage { liveUsageStep }
        }
        .task { await model.checkSetup() }
        // You were probably just in Terminal, signing in. Look again without being asked.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.checkSetup() }
        }
    }

    // MARK: - 1. Installed

    private var isInstalled: Bool {
        switch model.setup {
        case .checking, .notInstalled: return false
        case .ready, .signedOut, .notOnPlan, .unknown: return true
        }
    }

    @ViewBuilder
    private var installStep: some View {
        switch model.setup {
        case .checking:
            Step(number: 1, state: .waiting, title: "Claude Code is installed", detail: "Checking…")
        case .notInstalled:
            Step(number: 1, state: .problem, title: "Install Claude Code",
                 detail: "Tuloy couldn't find the \"claude\" command. Paste this into Terminal to install it, then come back.") {
                CommandBox(command: Commands.install)
                HStack {
                    Button("Open Terminal") { Commands.openTerminal() }
                        .buttonStyle(TuloyButtonStyle(prominent: true))
                    Button("Check Again") { Task { await model.checkSetup() } }
                        .buttonStyle(TuloyButtonStyle())
                }
            }
        default:
            Step(number: 1, state: .done, title: "Claude Code is installed",
                 detail: model.claudePath.map { "Found at \($0)" } ?? "Found.")
        }
    }

    // MARK: - 2. Signed in

    @ViewBuilder
    private var signInStep: some View {
        switch model.setup {
        case .checking, .notInstalled:
            Step(number: 2, state: .waiting, title: "Sign in with your Claude plan", detail: "After step 1.")
        case .ready(let plan):
            Step(number: 2, state: .done, title: "Signed in",
                 detail: plan.map { "With your Claude \($0.capitalized) plan." } ?? "With your Claude account.")
        case .unknown:
            Step(number: 2, state: .waiting, title: "Sign in with your Claude plan",
                 detail: "This version of Claude Code can't say whether it's signed in. Send a test ping to find out.")
        case .signedOut, .notOnPlan:
            Step(number: 2, state: .problem, title: "Sign in to Claude Code", detail: signInDetail) {
                HStack {
                    Button("Sign In…") {
                        Task { couldNotOpenTerminal = !(await model.signInWithTerminal()) }
                    }
                    .buttonStyle(TuloyButtonStyle(prominent: true))
                    Button(model.isCheckingSetup ? "Checking…" : "Check Again") { Task { await model.checkSetup() } }
                        .buttonStyle(TuloyButtonStyle())
                        .disabled(model.isCheckingSetup)
                }
                Text("Sign In opens Terminal and your browser. Sign in with the account that has your Claude plan, then come back: Tuloy checks again by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if couldNotOpenTerminal {
                    Text("Tuloy couldn't open Terminal. Open it yourself and run this:")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                CommandBox(command: Commands.signIn(model.claudePath))
            }
        }
    }

    private var isSignedIn: Bool {
        switch model.setup {
        case .ready, .unknown: return true
        case .checking, .notInstalled, .signedOut, .notOnPlan: return false
        }
    }

    private var signInDetail: String {
        if model.setup == .notOnPlan {
            return "Claude Code is set up with an API key, so pings would be billed and wouldn't start your window. Sign in with your Claude account instead."
        }
        return "This is the step most people are missing. It takes a minute, and you only do it once."
    }

    // MARK: - 3. Test ping

    /// The ping sent from this screen, once it's back.
    private var testResult: PingRecord? {
        guard let testedAt, let last = model.lastPing, last.date >= testedAt else { return nil }
        return last
    }

    private var testStep: some View {
        let result = testResult
        let state: StepState = result.map { $0.ok ? .done : .problem } ?? (model.lastPing?.ok == true ? .done : .todo)

        return Step(number: 3, state: state, title: "Send a test ping",
                    detail: "The real thing: one tiny message through Claude Code. If no window is open, this starts one now.") {
            Button(model.isPinging ? "Pinging…" : "Send Test Ping") {
                testedAt = Date()
                Task { await model.pingNow() }
            }
            // Until you're signed in, Sign In is the one bright button on this screen.
            .buttonStyle(TuloyButtonStyle(prominent: isSignedIn))
            .disabled(model.isPinging || !isInstalled)

            if let result {
                TestResult(ping: result, fix: model.problem?.recoverySuggestion)
            } else if let last = model.lastPing, !model.isPinging {
                Text("Last ping: \(Format.time(last.date)) · \(last.outcomeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 4. Live usage

    private var liveUsageStep: some View {
        Step(number: 4, state: model.isLiveUsageConnected ? .done : .optional, title: "Live usage (optional)",
             detail: "Tuloy already checks your usage every 5 minutes, free. This adds updates the moment you use Claude Code in Terminal, in between. The desktop app and claude.ai don't send them.") {
            if model.isLiveUsageConnected {
                Button("Disconnect") { model.setLiveUsage(connected: false) }
                    .buttonStyle(TuloyButtonStyle())
            } else if isConfirmingLiveUsage {
                Text("Connect adds a small script, ~/.tuloy/statusline.sh, and points the status line in ~/.claude/settings.json at it. Nothing else in that file changes and a copy is kept. If you already have a status line, it keeps working. Disconnect puts everything back.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Connect") {
                        model.setLiveUsage(connected: true)
                        isConfirmingLiveUsage = false
                    }
                    .buttonStyle(TuloyButtonStyle(prominent: true))
                    Button("Cancel") { isConfirmingLiveUsage = false }
                        .buttonStyle(TuloyButtonStyle())
                }
            } else {
                Button("Connect…") { isConfirmingLiveUsage = true }
                    .buttonStyle(TuloyButtonStyle())
            }
            Text(liveUsageStatus)
                .font(.caption)
                .foregroundStyle(model.liveUsageError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { model.refreshLiveUsage() }
    }

    private var liveUsageStatus: String {
        if let error = model.liveUsageError { return error }
        if let updated = model.liveUsageAt { return "On. Last update \(Format.time(updated))." }
        if model.isLiveUsageConnected { return "Connected. Usage shows up after your next reply in Claude Code in Terminal." }
        return model.canCheckUsage ? "Off. Usage still updates every 5 minutes." : "Off. Usage updates only with pings, since the 5-minute check is off (Preferences)."
    }
}

/// What a test ping came back with, in plain words.
struct TestResult: View {
    var ping: PingRecord
    var fix: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ping.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ping.ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(ping.ok ? "It works." : (ping.note ?? "The ping didn't get through."))
                    .fontWeight(.medium)
                if ping.ok {
                    Text(successDetail)
                        .foregroundStyle(.secondary)
                } else if let fix {
                    Text(fix)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((ping.ok ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var successDetail: String {
        var parts: [String] = []
        if let resetsAt = ping.resetsAt { parts.append("Your window resets at \(Format.time(resetsAt)).") }
        if let tokens = ping.tokens { parts.append("That ping used \(tokens) tokens.") }
        return parts.isEmpty ? "Claude answered." : parts.joined(separator: " ")
    }
}

/// One numbered step: a mark for how it stands, what it is, and whatever you need to do about it.
struct Step<Content: View>: View {
    var number: Int
    var state: StepState
    var title: String
    var detail: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                mark
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .problem:
            Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(.orange)
        case .todo, .waiting, .optional:
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(state == .todo ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .background(state == .todo ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Circle())
        }
    }
}

/// How a step stands: done, yours to do, waiting on an earlier step, needing a fix, or optional.
enum StepState {
    case done, todo, waiting, problem, optional
}

extension Step where Content == EmptyView {
    init(number: Int, state: StepState, title: String, detail: String) {
        self.init(number: number, state: state, title: title, detail: detail) { EmptyView() }
    }
}

/// The commands Tuloy shows you, in one place so every screen says the same thing.
enum Commands {
    /// The fact that surprises almost everyone. Said first, wherever signing in comes up.
    static let surprise = "Claude Code signs in separately. Being signed in to the Claude app or claude.ai isn't enough."
    static let install = "curl -fsSL https://claude.ai/install.sh | bash"
    static let status = "claude auth status"
    /// The plain ping, exactly as Tuloy runs it, split over lines so it reads well and still pastes.
    static let ping = """
        claude -p "\(ClaudeCLI.instruction)" \\
          --model haiku --tools "" \\
          --strict-mcp-config \\
          --output-format stream-json --verbose
        """

    /// Uses the full path when Tuloy knows it, in case "claude" isn't on your PATH yet.
    static func signIn(_ claudePath: String?) -> String {
        "\(claudePath ?? "claude") auth login"
    }

    static func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }
}

// MARK: - The step-by-step guide

/// A window to keep beside Terminal: every step and every command, start to finish.
struct GuideContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Tuloy to Claude")
                    .font(.title2.weight(.semibold))
                Text("About two minutes. This window stays on top, so you can follow along in Terminal.")
                    .foregroundStyle(.secondary)
            }

            GuideStep(number: 1, title: "Open Terminal",
                      text: "Press ⌘ Space, type Terminal and press Return. Or use this button.") {
                Button("Open Terminal") { Commands.openTerminal() }
                    .buttonStyle(TuloyButtonStyle())
            }

            GuideStep(number: 2, title: "Install Claude Code", done: isInstalled,
                      text: isInstalled
                          ? "Already installed\(model.claudePath.map { " at \($0)" } ?? ""). Skip this step."
                          : "Paste this into Terminal and press Return. Wait for it to finish, then close Terminal and open it again.") {
                if !isInstalled { CommandBox(command: Commands.install) }
            }

            GuideStep(number: 3, title: "Sign in", done: isSignedIn,
                      text: isSignedIn
                          ? "Already signed in. Skip this step."
                          : "Paste this and press Return. Your browser opens: sign in with the account that has your Claude plan (Pro or Max) and approve. Claude Code keeps this sign-in to itself, so being signed in to the desktop app or claude.ai isn't enough.") {
                if !isSignedIn { CommandBox(command: Commands.signIn(model.claudePath)) }
            }

            GuideStep(number: 4, title: "Check it worked",
                      text: "Paste this. You should see \"loggedIn\": true and \"authMethod\": \"claude.ai\". If it says false, do step 3 again.") {
                CommandBox(command: Commands.status)
                Button(model.isCheckingSetup ? "Checking…" : "Or Let Tuloy Check") { Task { await model.checkSetup() } }
                    .buttonStyle(TuloyButtonStyle())
                    .disabled(model.isCheckingSetup)
            }

            GuideStep(number: 5, title: "Send a test ping", done: model.lastPing?.ok == true,
                      text: "This is what Tuloy sends on schedule. A green tick means you're connected.") {
                Button(model.isPinging ? "Pinging…" : "Send Test Ping") { Task { await model.pingNow() } }
                    .buttonStyle(TuloyButtonStyle(prominent: true))
                    .disabled(model.isPinging)
                if let last = model.lastPing {
                    TestResult(ping: last, fix: model.problem?.recoverySuggestion)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Want to see exactly what Tuloy runs?")
                    .font(.headline)
                Text("This is the whole ping. You can run it in Terminal yourself:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                CommandBox(command: Commands.ping)
            }
        }
        .task { await model.checkSetup() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.checkSetup() }
        }
    }

    private var isInstalled: Bool {
        switch model.setup {
        case .checking, .notInstalled: return false
        default: return true
        }
    }

    private var isSignedIn: Bool {
        if case .ready = model.setup { return true }
        return false
    }
}

private struct GuideStep<Content: View>: View {
    var number: Int
    var title: String
    var done = false
    var text: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.tint, in: Circle())
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import AppKit
import SwiftUI

/// Help: the idea, where everything is, and answers to the things people ask.
struct HelpContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Help")
                .font(.title2.weight(.semibold))

            section("The idea in three lines") {
                Text("Claude gives you 5-hour windows. A window starts with your first message and resets 5 hours later. Tuloy sends one tiny message early, so that reset lands in the middle of your work instead of after it.")
                    .fixedSize(horizontal: false, vertical: true)
                Card {
                    DayTimeline(schedule: Schedule(), now: model.now)
                }
                Text("The pale block is the early window Tuloy opens. The dashed one is the fresh window you get.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            section("Where everything is") {
                Point(symbol: "menubar.arrow.up.rectangle", title: "The menu bar icon",
                      text: "Top right of your screen. Click it for a small panel with your usage, the countdown, Ping Now and Pause. Its More button has Settings, Help and Quit.")
                Point(symbol: "macwindow", title: "This window",
                      text: "Home shows what's happening. History lists every ping, with a square for each day. Schedule sets your fresh time. Messages sends Claude something of yours later, and keeps the reply. Connection checks Claude Code and sends test pings. Preferences changes how Tuloy looks and checks. While it's open, Tuloy shows in the Dock too.")
                Point(symbol: "rectangle.inset.topright.filled", title: "The mini window",
                      text: "A small panel that stays on top of everything. Open it from Home or the menu bar.")
            }

            section("What the menu bar icon is telling you") {
                Meaning(text: "Running. Nothing needs you.") { Glyph(status: .running, size: 16) }
                Meaning(text: "A ring or a countdown, if you chose one in Preferences: your usage, or the time until your fresh window. In Ultra, the ring shows whole hours (\"4h\") until two are left, then minutes, from 120 down.") {
                    Image(nsImage: Ring(progress: 0.62, text: "4h").image()).renderingMode(.template)
                }
                Meaning(text: "Paused. No pings until you resume.") { Glyph(status: .paused, size: 16) }
                Meaning(text: "Resting. Your weekly limit is used up, so Tuloy waits for it to reset.") { Glyph(status: .resting, size: 16) }
                Meaning(text: "Needs attention. Open Connection to see what and how to fix it. This shows whichever look you picked.") {
                    Glyph(status: .problem, size: 16)
                }
            }

            section("When your Mac is asleep") {
                Text("A sleeping or closed Mac pings late, if at all: only when macOS happens to wake it briefly, or when you open it, and only if that's within 5 hours. For a ping that's on time every day, let your iPhone send the early one:")
                    .fixedSize(horizontal: false, vertical: true)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Numbered(1, "Open Shortcuts, go to Automation and tap +.")
                        Numbered(2, "Choose Time of Day. Set your ping time (5 hours before your fresh time) and your days.")
                        Numbered(3, "Pick Run Immediately.")
                        Numbered(4, "Add the Ask Claude action with: Reply with only the word ok.")
                        Numbered(5, "Run it once with your phone locked to make sure it works.")
                    }
                }
                Text("Keep Tuloy running too. When your Mac wakes, it finds the window your phone opened and shows the real reset time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Questions") {
                ForEach(Question.all) { question in
                    QuestionRow(question: question)
                }
            }

            HStack {
                Button("Show the Welcome Again") { model.open(.setup) }
                    .buttonStyle(TuloyButtonStyle())
                Button("Open the Step-by-Step Guide") { model.open(.guide) }
                    .buttonStyle(TuloyButtonStyle())
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

/// A question and its answer.
struct Question: Identifiable {
    var ask: String
    var answer: String
    var id: String { ask }

    static let all = [
        Question(ask: "Where is Ping Now?",
                 answer: "In the panel under the menu bar icon, on Home, and in the mini window. It sends one ping right away, whatever the schedule says."),
        Question(ask: "My ping failed. What now?",
                 answer: "Open Connection. It shows which step isn't done and how to fix it. The usual cause is that Claude Code isn't signed in: it has its own sign-in, apart from the Claude desktop app and claude.ai."),
        Question(ask: "What does a ping cost?",
                 answer: "No money, and very little of your plan: the message \"hi\" to Claude's smallest model, with thinking off and a one-word reply, about 350 tokens. It counts toward your plan's usage like any message, never toward API billing or extra credit. History shows the exact count for each ping. Checking your usage every 5 minutes costs nothing at all: Claude Code answers it without sending Claude a message."),
        Question(ask: "What does Keep going do?",
                 answer: "After your fresh window, Tuloy starts a new one the moment each one ends, until the time you set. Your windows then run back to back, instead of waiting for your next message."),
        Question(ask: "How does Tuloy know my usage?",
                 answer: "Every 5 minutes it asks Claude Code, which reads it from your Claude account without sending Claude a message: free, and it starts no window. It sees your use from anywhere: the desktop app, claude.ai and your phone too. If you switch the check off in Preferences, the ring shows the time left instead, until a ping reports a percentage."),
        Question(ask: "How do scheduled messages work?",
                 answer: "In Messages, write what you'd ask Claude, then choose when (once, every day, or the moment your next fresh window opens), the folder, the model and effort, and what Claude may do there: just answer, read, edit files, or anything. Tuloy sends it through Claude Code at that time, in the background, and keeps the reply, with a way to carry on the conversation in Terminal. Your Mac has to be awake with Tuloy running; if it was asleep, the message goes when it wakes, up to 3 hours late."),
        Question(ask: "Can a scheduled message cost money?",
                 answer: "No. It uses your plan's allowance like any message (much more than a ping, depending on the model, effort and work), never an API key or paid extra usage: Tuloy holds it back if either would be used, and says so in its reply."),
        Question(ask: "Why did my ping go out late?",
                 answer: "Your Mac was asleep or off at ping time, or Tuloy wasn't running. History marks those pings \"Late\" and says which. Help, under When your Mac is asleep, shows how to have your iPhone send it on time."),
        Question(ask: "Does closing a window quit Tuloy?",
                 answer: "No. Tuloy keeps running in the menu bar. To quit, click the menu bar icon, then the More button in the corner of the panel, and choose Quit Tuloy."),
        Question(ask: "Is my Claude login safe?",
                 answer: "Tuloy never sees it. The official \"claude\" command signs in by itself, and Tuloy only runs that command. It can't use an API key either: those are removed before every ping."),
        Question(ask: "Does a ping interrupt what I'm doing in Claude?",
                 answer: "No. It's a separate, one-line conversation that isn't saved. If a window is already open, Tuloy waits for it to end before pinging."),
    ]
}

/// Tap a question to show its answer.
struct QuestionRow: View {
    var question: Question
    @State var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(question.ask)
                        .fontWeight(.medium)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(question.answer)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
    }
}

private struct Meaning<Icon: View>: View {
    var text: String
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 22)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Numbered: View {
    var number: Int
    var text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - About

/// What Tuloy is, said plainly: who makes it, what it does to your account, and what it can't promise.
struct AboutContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tuloy")
                    .font(.largeTitle.weight(.bold))
                Text("\u{201C}Keep going\u{201D} in Filipino. Version \(version).")
                    .foregroundStyle(.secondary)
            }

            Text("Tuloy is an independent app. It is not made, endorsed or supported by Anthropic. Claude is Anthropic's trademark.")
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            section("What it does",
                    "On a schedule you set, it sends one short message through Claude Code on your Mac, so your 5-hour usage window starts when you choose. It does not raise any limit: your window and weekly allowances stay exactly what your plan gives you.")
            section("What it uses",
                    "About \(model.lastPing?.tokens ?? 350) tokens per ping, from your own plan's usage: no money, no API billing, no extra credit. History shows the exact count for each one. The usage check every 5 minutes uses none.")
            section("What it never does",
                    "It never reads your login: the official \"claude\" command signs in by itself. It never uses an API key. It sends nothing anywhere except that one message to Claude, and every 5 minutes it asks Claude Code for your usage, which Claude Code looks up without sending Claude a message. It changes Claude Code's settings only if you choose Connect for live usage, and Disconnect puts them back.")
            section("What it can't promise",
                    "Anthropic can change how windows or Claude Code work at any time, and Tuloy may stop being useful when they do. Please read Anthropic's own terms and usage policy to decide whether using Tuloy is right for you.")

            HStack {
                Button("Anthropic's Usage Policy") { NSWorkspace.shared.open(URL(string: "https://www.anthropic.com/legal/aup")!) }
                    .buttonStyle(TuloyButtonStyle())
                Button("Consumer Terms") { NSWorkspace.shared.open(URL(string: "https://www.anthropic.com/legal/consumer-terms")!) }
                    .buttonStyle(TuloyButtonStyle())
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9"
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

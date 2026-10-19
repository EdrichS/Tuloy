import Foundation

/// A message you've written for Claude, and when and how Tuloy sends it.
///
/// Tuloy sends it through Claude Code, like a ping, but it's a real piece of work: it can use
/// a bigger model, think harder, and read or change files in a folder you choose.
struct ScheduledMessage: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// A short name, for the list and the notification.
    var title = ""
    /// What Claude is asked.
    var prompt = ""
    var when = When.once(Date().addingTimeInterval(60 * 60))
    /// A model alias ("haiku", "sonnet", "opus", "fable") or a full model name. Empty: Claude Code's default.
    var model = ""
    /// "low", "medium", "high", "xhigh" or "max". Empty: Claude Code's default.
    var effort = ""
    /// The folder Claude works in. Empty: none (Tuloy's own folder, with nothing in it).
    var folder = ""
    var access = Access.answerOnly
    /// Lets Claude search the web and read pages, whatever else it may do.
    var canUseWeb = false
    /// Your CLAUDE.md files, MCP servers, hooks and plugins. Off: Claude Code's safe mode.
    var usesYourSetup = true
    /// Keeps the conversation, so you can carry on with it in Claude Code afterwards.
    var keepsConversation = true
    /// Added to Claude Code's own instructions.
    var instructions = ""
    /// If your Mac was asleep (or Tuloy wasn't running) at the time, send it when it can, up to
    /// three hours late. Off: skip it, and note that it was missed.
    var sendsLate = true
    var notifies = true
    /// How long it may run before Tuloy stops it, in minutes. 0: no limit, it runs until Claude is done
    /// (or you press Stop).
    var minutesAllowed = 30
    /// Switched off: kept, but never sent. A one-off switches itself off once sent.
    var isOn = true
    /// When it goes next. Worked out by the Engine.
    var nextRun: Date?

    enum When: Codable, Equatable, Sendable {
        /// Once, at this moment.
        case once(Date)
        /// On these days (1 = Sunday … 7 = Saturday), at this many minutes after midnight.
        case daily(minutes: Int, weekdays: [Int])
        /// The moment your next fresh window opens: when the open window resets, or Tuloy's planned one.
        case nextFreshWindow
    }

    /// What Claude may do while working on it. Claude Code is told to refuse anything more,
    /// without stopping to ask, since nobody is there to answer.
    enum Access: String, Codable, CaseIterable, Identifiable, Sendable {
        /// No tools: Claude only writes a reply.
        case answerOnly
        /// May read and search the folder. Changes nothing.
        case read
        /// May also create and edit files in the folder. Runs no commands.
        case edit
        /// Anything, without asking: edits, commands, the lot.
        case full

        var id: Self { self }

        var label: String {
            switch self {
            case .answerOnly: return "Answer only"
            case .read: return "Read the folder"
            case .edit: return "Read and edit files in the folder"
            case .full: return "Anything, without asking"
            }
        }

        var explanation: String {
            switch self {
            case .answerOnly: return "No tools. Claude writes a reply and nothing else. Uses the least."
            case .read: return "Claude can open and search files in the folder. It can't change anything or run commands."
            case .edit: return "Claude can also create and change files in the folder. It can't run commands, and can't touch anything outside the folder."
            case .full: return "Claude can change any file and run any command, with nobody asked first. Only for folders you'd let a stranger work in, ideally under version control."
            }
        }
    }

    /// True when it's ready to save: it has something to say.
    var isComplete: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The name to show: the title, or the start of the message.
    var name: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let first = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.isEmpty ? "Untitled message" : String(first.prefix(40)) + (first.count > 40 ? "…" : "")
    }

    /// The folder Claude Code runs in.
    var folderURL: URL? {
        folder.isEmpty ? nil : URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: - When it goes

    /// The next time this goes out after `date`, by its own rule. (A fresh-window message is
    /// worked out by the Engine, which knows your windows.)
    func nextTime(after date: Date, calendar: Calendar) -> Date? {
        switch when {
        case .once(let moment):
            return moment
        case .daily(let minutes, let weekdays):
            let start = calendar.startOfDay(for: date)
            for offset in 0...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                      weekdays.contains(calendar.component(.weekday, from: day)),
                      let time = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                      time > date
                else { continue }
                return time
            }
            return nil
        case .nextFreshWindow:
            return nil
        }
    }

    var repeats: Bool {
        if case .daily = when { return true }
        return false
    }
}

/// One time a message went out (or should have), and what came back.
struct MessageRun: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case running
        /// Claude answered.
        case done
        /// It went, but didn't work.
        case failed
        /// Stopped by you, or because it ran past its time.
        case stopped
        /// Not sent: the Mac was asleep for too long, or something would have made it cost money.
        case notSent
    }

    var id = UUID()
    var messageID: UUID
    var title: String
    var started: Date
    var finished: Date?
    var outcome: Outcome
    /// Claude's reply, or why it didn't work.
    var text: String
    var tokens: Int?
    /// The conversation, if it was kept, for carrying on in Claude Code.
    var sessionID: String?
    var folder: String
    /// The model Claude Code used, as it named it.
    var model: String?
    /// Things Claude wanted to do but wasn't allowed to ("Edit", "Bash", …).
    var refused: [String] = []
    /// Set when it went out late, and why.
    var late: PingRecord.Lateness?
    /// When the window this message landed in resets, if Claude Code said.
    var windowResets: Date?
    /// True when this message opened that window.
    var openedWindow = false
}

/// What Claude Code came back with, after one message.
struct MessageOutcome: Sendable {
    /// The reply, or why there isn't one.
    var result: Result<String, PingError>
    /// The usage report and the token count, read the same way as a ping's.
    var report = PingReport()
    var sessionID: String?
    var model: String?
    var version: String?
    /// True if Claude Code said it used an API key: then this was billed, not taken from your plan.
    var usedAPIKey = false
    var refused: [String] = []
}

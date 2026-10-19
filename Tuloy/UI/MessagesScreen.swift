import AppKit
import SwiftUI

/// Messages: write something for Claude, choose when it goes and how, and read the reply later.
struct MessagesContent: View {
    @Bindable var model: AppModel
    /// The message open in the editor: a new one, or a copy of one being changed.
    @State private var editing: ScheduledMessage?
    @State private var deleting: ScheduledMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if model.messages.isEmpty {
                ideas
            } else {
                ForEach(model.messages) { message in
                    MessageRow(model: model, message: message, edit: { editing = message }, delete: { deleting = message })
                }
            }

            replies
        }
        .sheet(item: $editing) { message in
            MessageEditor(model: model, draft: message, isNew: !model.messages.contains { $0.id == message.id }) { saved in
                if let saved { model.save(saved) }
                editing = nil
            }
        }
        .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { model.deleteMessage(deleting.id) }
                deleting = nil
            }
        } message: {
            Text("Its replies stay below.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Messages")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("New Message") { editing = ScheduledMessage() }
                    .buttonStyle(TuloyButtonStyle(prominent: true))
            }
            Text("Write something for Claude and choose when it goes: once, every day, or the moment your next fresh window opens. Tuloy sends it through Claude Code, in a folder you pick, with the model and effort you pick, and keeps the reply here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Each message uses your plan's allowance like any message you send, more for bigger models, higher effort and longer work. Never money: the same guards as pings apply. A message sent while no window is open starts one, just as a ping does. Pause stops pings, not messages: each message has its own switch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// With no messages yet: what they're good for.
    private var ideas: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Some ideas")
                    .font(.headline)
                Point(symbol: "sunrise", title: "Every weekday at 8:30 AM",
                      text: "\u{201C}Read the changes in this project since yesterday and list what's left to do.\u{201D} Waiting for you when you sit down.")
                Point(symbol: "arrow.clockwise.circle", title: "At my next fresh window",
                      text: "A big job, sent the moment your allowance refills, so it has a full window to work in.")
                Point(symbol: "moon.stars", title: "Once, tonight at 11 PM",
                      text: "\u{201C}Go through the docs folder and note anything out of date.\u{201D} Read in the morning.")
                Button("Write Your First Message") { editing = ScheduledMessage() }
                    .buttonStyle(TuloyButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var replies: some View {
        Text("Replies")
            .font(.headline)
            .padding(.top, 6)
        if model.messageRuns.isEmpty {
            Text("Nothing sent yet. Each time a message goes out, what came back shows up here.")
                .foregroundStyle(.secondary)
        }
        ForEach(model.messageRuns) { run in
            RunRow(model: model, run: run)
        }
    }
}

// MARK: - One message in the list

struct MessageRow: View {
    let model: AppModel
    var message: ScheduledMessage
    var edit: () -> Void
    var delete: () -> Void

    private var isSending: Bool { model.sendingMessage == message.id }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.name)
                            .font(.headline)
                        Text(MessageText.schedule(of: message, now: model.now))
                            .foregroundStyle(message.isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        Text(MessageText.settings(of: message))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("On", isOn: Binding(get: { message.isOn }, set: { model.setMessage(message.id, isOn: $0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(message.isOn ? "On: it will be sent" : "Off: kept, but not sent")
                }

                Text(message.prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if isSending {
                        ProgressView().controlSize(.small)
                        Text("Claude is working on it…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Stop") { model.stopSending() }
                            .buttonStyle(TuloyButtonStyle())
                            .help("Ask Claude Code to stop. Anything it has already done stays done.")
                    } else {
                        Button("Send Now") { model.sendNow(message.id) }
                            .buttonStyle(TuloyButtonStyle())
                            .disabled(model.sendingMessage != nil)
                            .help(model.sendingMessage != nil ? "Another message is being sent. One at a time." : "Send it now. Its own schedule stays as it is.")
                        Button("Edit…", action: edit)
                            .buttonStyle(TuloyButtonStyle())
                    }
                    Spacer()
                    Menu {
                        Button("Duplicate") {
                            var copy = message
                            copy.id = UUID()
                            copy.title = message.name + " copy"
                            copy.isOn = false
                            model.save(copy)
                        }
                        Button("Delete…", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More for this message")
                }
            }
        }
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Send Now") { model.sendNow(message.id) }.disabled(model.sendingMessage != nil)
            Divider()
            Button("Delete…", role: .destructive, action: delete)
        }
    }
}

// MARK: - One reply

struct RunRow: View {
    let model: AppModel
    var run: MessageRun
    @State private var isOpen: Bool
    @State private var couldNotOpen = false

    init(model: AppModel, run: MessageRun, isOpenForTest: Bool = false) {
        self.model = model
        self.run = run
        _isOpen = State(initialValue: isOpenForTest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    mark
                    Text(run.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(Format.when(run.started, now: model.now))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    if let tokens = run.tokens {
                        Text("\(tokens.formatted()) tokens")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout)

            if !isOpen, !run.text.isEmpty {
                Text(run.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 26)
            }

            if isOpen { details.padding(.leading, 26) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var mark: some View {
        switch run.outcome {
        case .running:
            ProgressView().controlSize(.small).frame(width: 18)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 18)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange).frame(width: 18)
        case .stopped:
            Image(systemName: "stop.circle.fill").foregroundStyle(.secondary).frame(width: 18)
        case .notSent:
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary).frame(width: 18)
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if run.outcome == .running {
                Text("Claude is working on it. The reply appears here when it's done.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(run.text.isEmpty ? "Claude finished without a written reply." : run.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 320)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 6) {
                    Button("Copy Reply") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(run.text, forType: .string)
                    }
                    .buttonStyle(TuloyButtonStyle())
                    if run.sessionID != nil {
                        Button("Continue in Terminal") {
                            Task { couldNotOpen = !(await model.continueInTerminal(run)) }
                        }
                        .buttonStyle(TuloyButtonStyle())
                        .help("Opens Terminal on this conversation, in the same folder, so you can carry on with Claude")
                    }
                }
                if couldNotOpen, let command = MessageText.resumeCommand(for: run) {
                    Text("Tuloy couldn't open Terminal. Run this there:")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    CommandBox(command: command)
                }
            }

            ForEach(MessageText.facts(about: run, now: model.now), id: \.self) { fact in
                Text(fact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Writing one

struct MessageEditor: View {
    let model: AppModel
    @State var draft: ScheduledMessage
    var isNew: Bool
    /// Called with the message to save, or nil to cancel.
    var done: (ScheduledMessage?) -> Void

    @State private var askingAboutFullAccess = false
    @State private var otherModel = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                messageSection
                whenSection
                folderSection
                accessSection
                modelSection
                moreSection
                commandSection
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)

            Divider()
            HStack {
                if let problem {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { done(nil) }
                    .buttonStyle(TuloyButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Save Message" : "Save Changes") { done(draft) }
                    .buttonStyle(TuloyButtonStyle(prominent: true))
                    .disabled(problem != nil)
            }
            .padding(14)
        }
        .frame(width: 600, height: 680)
        .onAppear { otherModel = !draft.model.isEmpty && !MessageText.models.contains { $0.alias == draft.model } }
        .confirmationDialog("Let Claude do anything, without asking?", isPresented: $askingAboutFullAccess) {
            Button("Allow Anything") { draft.access = .full }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude will be able to change or delete any file and run any command, and nobody will be asked first, because nobody is there. Only for a folder you'd trust a stranger with, ideally under version control so you can undo it.")
        }
    }

    /// What's stopping it from being saved, if anything.
    private var problem: String? {
        if !draft.isComplete { return "Write the message first." }
        if case .once(let moment) = draft.when, moment < model.now.addingTimeInterval(-60) { return "That time has passed." }
        if case .daily(_, let weekdays) = draft.when, weekdays.isEmpty { return "Pick at least one day." }
        if otherModel, draft.model.trimmingCharacters(in: .whitespaces).isEmpty { return "Type the model's name, or pick one." }
        return nil
    }

    // MARK: Sections

    private var messageSection: some View {
        Section {
            TextField("Name", text: $draft.title, prompt: Text("Optional, e.g. Morning summary"))
            VStack(alignment: .leading, spacing: 4) {
                Text("Message")
                TextEditor(text: $draft.prompt)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Message")
            }
        } header: {
            Text("What to ask Claude")
        } footer: {
            Footer("Write it the way you would in Claude Code. Claude can't ask you anything back, so say everything it needs.")
        }
    }

    private var whenSection: some View {
        Section {
            Picker("When", selection: whenKind) {
                Text("Once").tag(0)
                Text("Every day").tag(1)
                Text("Next fresh window").tag(2)
            }
            .pickerStyle(.segmented)

            switch draft.when {
            case .once(let moment):
                DatePicker("At", selection: Binding(get: { moment }, set: { draft.when = .once($0) }),
                           in: model.now..., displayedComponents: [.date, .hourAndMinute])
            case .daily(let minutes, let weekdays):
                DatePicker("At", selection: Binding(get: { MessageText.date(forMinutes: minutes) },
                                                    set: { draft.when = .daily(minutes: MessageText.minutes(for: $0), weekdays: weekdays) }),
                           displayedComponents: .hourAndMinute)
                LabeledContent("On") {
                    WeekdayPicker(selection: Binding(get: { Set(weekdays) },
                                                     set: { draft.when = .daily(minutes: minutes, weekdays: $0.sorted()) }))
                }
            case .nextFreshWindow:
                LabeledContent("That's") {
                    Text(model.freshWindowTarget.map { Format.when($0, now: model.now) } ?? "not planned yet")
                }
            }
            Toggle(isOn: $draft.sendsLate) {
                Text("Send it late if my Mac was asleep")
                Text("Up to 3 hours late. Off: it's skipped, and the reply list says so.")
            }
        } header: {
            Text("When")
        } footer: {
            Footer(whenFooter)
        }
    }

    private var whenFooter: String {
        switch draft.when {
        case .nextFreshWindow:
            return "A minute after your open window resets, or after the fresh window Tuloy has planned. If you open a window yourself first, it moves to that one's end. Sent once."
        case .daily:
            return "Your Mac has to be awake, with Tuloy running, for it to go on time."
        case .once:
            return "If no window is open then, this message starts one, just as a ping would."
        }
    }

    private var whenKind: Binding<Int> {
        Binding(get: {
            switch draft.when {
            case .once: return 0
            case .daily: return 1
            case .nextFreshWindow: return 2
            }
        }, set: { kind in
            switch kind {
            case 0: draft.when = .once(model.now.addingTimeInterval(60 * 60))
            case 1: draft.when = .daily(minutes: 9 * 60, weekdays: [2, 3, 4, 5, 6])
            default: draft.when = .nextFreshWindow
            }
        })
    }

    private var folderSection: some View {
        Section {
            LabeledContent("Folder") {
                Text(draft.folder.isEmpty ? "None" : (draft.folder as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(draft.folder.isEmpty ? .secondary : .primary)
            }
            HStack {
                Button("Choose Folder…") { chooseFolder() }
                    .buttonStyle(TuloyButtonStyle())
                if !draft.folder.isEmpty {
                    Button("No Folder") { draft.folder = "" }
                        .buttonStyle(TuloyButtonStyle())
                }
            }
        } header: {
            Text("Where")
        } footer: {
            Footer(draft.folder.isEmpty
                   ? "With no folder, Claude has no project to look at: good for questions and writing."
                   : "Claude Code works here, with this folder's CLAUDE.md. Only choose folders you trust: an unattended run skips Claude Code's \u{201C}do you trust this folder?\u{201D} question.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "The folder Claude works in for this message."
        if !draft.folder.isEmpty { panel.directoryURL = draft.folderURL }
        if panel.runModal() == .OK, let url = panel.url {
            draft.folder = url.path(percentEncoded: false)
            if draft.access == .answerOnly { draft.access = .read }
        }
    }

    private var accessSection: some View {
        Section {
            Picker("Claude may", selection: Binding(get: { draft.access }, set: { access in
                if access == .full, draft.access != .full { askingAboutFullAccess = true } else { draft.access = access }
            })) {
                ForEach(ScheduledMessage.Access.allCases) { access in
                    Text(access.label).tag(access)
                }
            }
            .pickerStyle(.radioGroup)

            Text(draft.access.explanation)
                .font(.callout)
                .foregroundStyle(draft.access == .full ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $draft.canUseWeb) {
                Text("Search the web and read pages")
                Text(draft.access == .full ? "Included in \u{201C}Anything\u{201D}." : "For questions about today's news, docs online, and so on.")
            }
            .disabled(draft.access == .full)
        } header: {
            Text("What Claude may do")
        } footer: {
            Footer("Nobody is there to approve anything, so Claude Code refuses whatever this doesn't allow, and the reply says what it wanted to do.")
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Model", selection: Binding(get: { otherModel ? "other" : draft.model }, set: { choice in
                otherModel = choice == "other"
                draft.model = otherModel ? "" : choice
                if draft.model == "haiku" { draft.effort = "" }
            })) {
                ForEach(MessageText.models, id: \.alias) { model in
                    Text(model.label).tag(model.alias)
                }
                Text("Other…").tag("other")
            }
            if otherModel {
                TextField("Model name", text: $draft.model, prompt: Text("e.g. claude-sonnet-4-5"))
            }
            Picker("Effort", selection: $draft.effort) {
                ForEach(MessageText.efforts, id: \.level) { effort in
                    Text(effort.label).tag(effort.level)
                }
            }
            .disabled(draft.model == "haiku")
        } header: {
            Text("Model and effort")
        } footer: {
            Footer(draft.model == "haiku"
                   ? "Haiku has no effort levels."
                   : "Higher effort means Claude thinks longer: better for hard problems, and more of your allowance. Not every plan includes every model; if yours doesn't, the reply says so.")
        }
    }

    private var moreSection: some View {
        Section {
            Toggle(isOn: $draft.keepsConversation) {
                Text("Keep the conversation")
                Text("So you can carry on with it afterwards (Continue in Terminal, or Claude Code's /resume list).")
            }
            Toggle(isOn: $draft.notifies) {
                Text("Notify me when it's done")
            }
            Toggle(isOn: $draft.usesYourSetup) {
                Text("Use my Claude Code setup")
                Text("Your CLAUDE.md files, MCP servers, hooks and plugins. Off: Claude Code's safe mode, without them.")
            }
            Picker(selection: $draft.minutesAllowed) {
                ForEach([10, 30, 60, 120], id: \.self) { minutes in
                    Text(minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours").tag(minutes)
                }
                Divider()
                Text("Never: let it finish").tag(0)
            } label: {
                Text("Stop it after")
                Text(draft.minutesAllowed == 0
                     ? "No limit: it runs until Claude is done. Stop is always there, and quitting Tuloy stops it too."
                     : "A safety net, in case Claude gets stuck or a job runs longer than you meant.")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Extra instructions")
                TextField("Extra instructions", text: $draft.instructions, prompt: Text("Optional, e.g. Keep the reply under 200 words."), axis: .vertical)
                    .lineLimit(2...4)
                    .labelsHidden()
            }
        } header: {
            Text("More")
        }
    }

    private var commandSection: some View {
        Section {
            CommandBox(command: MessageText.command(for: draft))
        } header: {
            Text("What Tuloy will run")
        } footer: {
            Footer("Your message goes to Claude Code directly, not as part of this line. Like a ping, it never uses an API key.")
        }
    }
}

// MARK: - Words

/// The text the Messages screen shows, kept together so every place says the same thing.
enum MessageText {
    static let models: [(alias: String, label: String)] = [
        ("", "Claude Code's default"),
        ("haiku", "Haiku: quickest, uses the least"),
        ("sonnet", "Sonnet"),
        ("opus", "Opus: most capable, uses the most"),
        ("fable", "Fable"),
    ]

    static let efforts: [(level: String, label: String)] = [
        ("", "Claude Code's default"),
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
        ("xhigh", "Extra high"),
        ("max", "Max"),
    ]

    /// "Every weekday at 9:00 AM. Next: Tue 9:00 AM", and so on.
    static func schedule(of message: ScheduledMessage, now: Date) -> String {
        let rule: String
        switch message.when {
        case .once(let moment):
            rule = "Once, \(Format.when(moment, now: now))"
        case .daily(let minutes, let weekdays):
            rule = "\(days(weekdays)) at \(date(forMinutes: minutes).formatted(date: .omitted, time: .shortened))"
        case .nextFreshWindow:
            rule = "At your next fresh window"
        }
        guard message.isOn else {
            if !message.repeats, message.nextRun == nil { return "\(rule). Sent, or switched off." }
            return "\(rule). Off."
        }
        guard let next = message.nextRun else { return "\(rule). Nothing planned yet." }
        if case .once = message.when { return rule }
        return "\(rule). Next: \(Format.when(next, now: now))"
    }

    /// "Sonnet · high effort · ~/project · Read the folder"
    static func settings(of message: ScheduledMessage) -> String {
        var parts = [models.first { $0.alias == message.model }.map { $0.alias.isEmpty ? "Default model" : $0.alias.capitalized } ?? message.model]
        if !message.effort.isEmpty { parts.append("\(efforts.first { $0.level == message.effort }?.label.lowercased() ?? message.effort) effort") }
        parts.append(message.folder.isEmpty ? "no folder" : (message.folder as NSString).abbreviatingWithTildeInPath)
        parts.append(message.access.label)
        if message.canUseWeb, message.access != .full { parts.append("web") }
        return parts.joined(separator: " · ")
    }

    private static func days(_ weekdays: [Int]) -> String {
        let set = Set(weekdays)
        if set.count == 7 { return "Every day" }
        if set == [2, 3, 4, 5, 6] { return "Every weekday" }
        if set == [1, 7] { return "Weekends" }
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return order.filter(set.contains).map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }

    /// The command, as you could type it, without the message.
    static func command(for message: ScheduledMessage) -> String {
        let quote = { (text: String) -> String in
            text.allSatisfy { $0.isLetter || $0.isNumber || "-_./,:=".contains($0) } && !text.isEmpty
                ? text : "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let line = "claude " + ClaudeCLI.messageArguments(for: message).map(quote).joined(separator: " ")
        guard !message.folder.isEmpty else { return line }
        return "cd \(quote((message.folder as NSString).abbreviatingWithTildeInPath)) && \(line)"
            .replacingOccurrences(of: "'~/", with: "~/'")
    }

    /// The command that carries on a kept conversation, from its folder.
    static func resumeCommand(for run: MessageRun) -> String? {
        guard let id = run.sessionID else { return nil }
        let folder = run.folder.isEmpty ? "~/.tuloy" : (run.folder as NSString).abbreviatingWithTildeInPath
        let quoted = folder.contains(" ") ? "'\(folder)'" : folder
        return "cd \(quoted) && claude --resume \(id)"
    }

    /// The small print under a reply.
    static func facts(about run: MessageRun, now: Date) -> [String] {
        var facts: [String] = []
        if let finished = run.finished, run.outcome != .notSent {
            let seconds = Int(finished.timeIntervalSince(run.started))
            let took = seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
            facts.append("Sent \(Format.when(run.started, now: now)), took \(took)" + (run.model.map { ", on \($0)" } ?? "") + ".")
        }
        if let late = run.late {
            let why = late.reason == .asleep ? "your Mac was asleep" : "Tuloy wasn't running"
            facts.append("Late: \(why) at \(late.due.formatted(date: .omitted, time: .shortened)).")
        }
        if !run.refused.isEmpty {
            let tools = Array(Set(run.refused)).sorted().joined(separator: ", ")
            facts.append("Claude wanted to use \(tools) but wasn't allowed. If it should, give the message more access.")
        }
        if let resets = run.windowResets {
            facts.append(run.openedWindow
                         ? "No window was open, so this message started one. It resets \(Format.when(resets, now: now))."
                         : "It landed in your open window, which resets \(Format.when(resets, now: now)).")
        }
        if run.folder.isEmpty == false {
            facts.append("Folder: \((run.folder as NSString).abbreviatingWithTildeInPath)")
        }
        return facts
    }

    static func date(forMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(for date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

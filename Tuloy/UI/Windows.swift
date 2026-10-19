import AppKit
import SwiftUI

/// Tuloy's windows. The menu bar item is always there; these open when you ask.
/// Closing any of them leaves Tuloy running in the menu bar.
enum WindowID: String {
    /// The main window: status, history, schedule, messages, connection, preferences and help.
    case main
    /// The welcome, shown the first time you open Tuloy.
    case setup
    /// The small one that floats above your other windows.
    case mini
    /// Step-by-step instructions for connecting to Claude Code, to keep beside Terminal.
    case guide
}

/// The screens in the main window.
enum MainTab: String, CaseIterable, Identifiable {
    case home, history, schedule, messages, connection, preferences, help, about

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .history: return "square.grid.3x3"
        case .schedule: return "clock"
        case .messages: return "paperplane"
        case .connection: return "link"
        case .preferences: return "slider.horizontal.3"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        }
    }
}

/// Reaches the real window behind a SwiftUI view, for the few things SwiftUI can't set on macOS 14
/// (like floating above other windows).
struct WindowConfigurator: NSViewRepresentable {
    var configure: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Reader()
        view.configure = configure
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class Reader: NSView {
        var configure: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure?(window) }
        }
    }
}

extension View {
    /// Tells the model when this window opens and closes, for the Dock icon.
    func tracksWindow(_ id: WindowID, model: AppModel) -> some View {
        onAppear { model.window(id, isOpen: true) }
            .onDisappear { model.window(id, isOpen: false) }
    }

    /// Keeps this window above your other windows, on every desktop.
    func floatingWindow(movableByBackground: Bool = false) -> some View {
        background(WindowConfigurator { window in
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.isMovableByWindowBackground = movableByBackground
        })
    }
}

// MARK: - Shared pieces

/// Tuloy's buttons: filled for the main action, quiet for the rest.
struct TuloyButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration, prominent: prominent)
    }

    private struct Label: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 7))
                .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

/// A switch with its label on the left and the switch on the right edge, as in Preferences.
/// For places outside a settings form, where macOS would put the switch right after the words.
struct SwitchRow: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rounded panel that groups related things.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A command to run in Terminal, with a button that copies it.
struct CommandBox: View {
    var command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .buttonStyle(TuloyButtonStyle())
        }
        .padding(.leading, 10)
        .padding([.vertical, .trailing], 6)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The big ring: how much of your window is used, or how long until it resets.
struct StatusRing: View {
    let model: AppModel
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
            VStack(spacing: 0) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.26, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    Text(center)
                        .font(.system(size: size * 0.25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text(label)
                    .font(.system(size: max(9, size * 0.11)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(size * 0.045)
        .frame(width: size, height: size)
        // An old reading looks old: faded, until it's refreshed.
        .opacity(model.isUsageStale ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(center) \(label)")
    }

    /// With a problem, a pause or a rest, the ring shows a symbol instead of a number.
    private var symbol: String? {
        switch model.status {
        case .problem: return "exclamationmark.triangle.fill"
        case .paused: return "pause.fill"
        case .resting: return "moon.zzz.fill"
        case .running: return nil
        }
    }

    private var center: String {
        if let percent = model.usagePercent { return "\(percent)%" }
        return Format.countdown(to: model.currentWindow?.resetsAt, from: model.now)
    }

    private var label: String {
        switch model.status {
        case .problem: return "check"
        case .paused: return "paused"
        case .resting: return "resting"
        case .running:
            if model.usagePercent != nil { return "used" }
            return model.currentWindow == nil ? "no window" : "left"
        }
    }

    /// The share used when Claude Code has said. Otherwise, how far through the 5 hours you are.
    private var progress: Double {
        guard model.status == .running, let window = model.currentWindow else { return 0 }
        if let percent = window.percent { return Double(percent) / 100 }
        let left = window.resetsAt.timeIntervalSince(model.now) / Schedule.window
        return min(1, max(0, 1 - left))
    }

    private var tint: Color {
        if model.status == .problem { return .orange }
        if model.status != .running { return .secondary }
        return (model.usagePercent ?? 0) >= 90 ? .orange : .accentColor
    }
}

extension PingRecord {
    /// Why it was sent, in words.
    var kindText: String {
        switch kind {
        case .scheduled: return "Scheduled"
        case .keepGoing: return "Keep going"
        case .manual: return "By you"
        }
    }

    /// True for a ping that got through only to find the window already used up.
    var hitTheLimit: Bool { ok && note != nil }

    /// A tick, a cross, or a dash for a ping that found the window used up.
    var mark: String { hitTheLimit ? "–" : ok ? "✓" : "✕" }

    /// What came of it: the problem, or when the window resets.
    var outcomeText: String {
        if hitTheLimit, let note, let resetsAt { return "\(note), resets \(Format.time(resetsAt))" }
        if let note { return note }
        if let resetsAt { return "Fresh at \(Format.time(resetsAt))" }
        return ok ? "Sent" : "Didn't get through"
    }

    /// "6:00 AM", or "6:00 – 8:30 AM" for a run of the same failure.
    var timeText: String {
        guard let firstDate, (count ?? 1) > 1 else { return date.formatted(date: .omitted, time: .shortened) }
        return (firstDate..<max(date, firstDate)).formatted(.interval.hour().minute())
    }

    /// "(6 times)" for a run of the same failure.
    var timesText: String? {
        (count ?? 1) > 1 ? "(\(count ?? 1) times)" : nil
    }

    /// "Late: your Mac was asleep at 6:00 AM", for a scheduled ping that went out late.
    var lateText: String? {
        guard let late else { return nil }
        let due = late.due.formatted(date: .omitted, time: .shortened)
        switch late.reason {
        case .asleep: return "Late: your Mac was asleep at \(due)"
        case .notRunning: return "Late: Tuloy wasn't running at \(due)"
        }
    }
}

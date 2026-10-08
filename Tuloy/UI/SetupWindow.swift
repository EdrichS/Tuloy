import SwiftUI

/// The welcome window: four short steps that take you from "just installed" to "it's running".
/// Shown the first time you open Tuloy, and any time from Help.
struct SetupWindow: View {
    @Bindable var model: AppModel
    @State private var step = SetupStep.welcome
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                SetupPage(model: model, step: step)
                    .padding(24)
            }
            Divider()
            SetupFooter(step: step, back: back, next: next)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 560, height: 580)
    }

    private func back() {
        if let previous = SetupStep(rawValue: step.rawValue - 1) { step = previous }
    }

    private func next() {
        if let following = SetupStep(rawValue: step.rawValue + 1) {
            step = following
        } else {
            // Finished: hand over to the main window.
            model.open(.main, tab: .home)
            dismissWindow(id: WindowID.setup.rawValue)
        }
    }
}

enum SetupStep: Int, CaseIterable {
    case welcome, connect, schedule, done

    var title: String {
        switch self {
        case .welcome: return "Welcome to Tuloy"
        case .connect: return "Connect to Claude"
        case .schedule: return "Pick your fresh time"
        case .done: return "You're set"
        }
    }

    var nextTitle: String {
        switch self {
        case .welcome: return "Get Started"
        case .connect, .schedule: return "Continue"
        case .done: return "Open Tuloy"
        }
    }
}

/// One page of the welcome.
struct SetupPage: View {
    @Bindable var model: AppModel
    var step: SetupStep

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(step.title)
                .font(.largeTitle.weight(.bold))

            switch step {
            case .welcome: welcome
            case .connect: connect
            case .schedule: schedule
            case .done: done
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 1. Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tuloy (\u{201C}keep going\u{201D} in Filipino) makes your Claude allowance reset when you want it to.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            Point(symbol: "hourglass", title: "Claude gives you 5-hour windows",
                  text: "A window starts with your first message and resets 5 hours later. Start at 9:00 AM and you wait until 2:00 PM for a refill.")
            Point(symbol: "paperplane", title: "Tuloy starts one early",
                  text: "It sends one tiny message hours before you sit down. That window runs out while you work, and you get a fresh one mid-session.")
            Point(symbol: "menubar.arrow.up.rectangle", title: "It lives in your menu bar",
                  text: "No Dock icon. Look for the small icon at the top right of your screen. This window and a mini one are there whenever you want them.")

            Card {
                DayTimeline(schedule: Schedule(), now: model.now)
            }
            Text("An example day: a ping at 6:00 AM means a fresh window at 11:00 AM.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 2. Connect

    private var connect: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tuloy sends its message through Claude Code, Anthropic's command-line app, so it counts toward your plan and Tuloy never sees your login. Three things to tick off:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ConnectionChecklist(model: model, showsLiveUsage: false)
            Button("Open the Step-by-Step Guide") { model.open(.guide) }
                .buttonStyle(TuloyButtonStyle())
            Text("Not ready? You can continue and finish this later in the Connection screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 3. Schedule

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("When would you like your allowance to refill? A good choice is two or three hours after you usually start.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker("Fresh window at", selection: $model.freshTime, displayedComponents: .hourAndMinute)
                    LabeledContent("On") {
                        WeekdayPicker(selection: $model.weekdays)
                    }
                    Toggle(isOn: $model.keepGoing) {
                        Text("Keep going")
                        Text("Start a new window each time one ends.")
                    }
                    if model.keepGoing {
                        DatePicker("Until", selection: $model.untilTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            Card {
                DayTimeline(schedule: model.schedule, now: model.now)
            }
            Text(model.schedule.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 4. Done

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                HStack(spacing: 14) {
                    StatusRing(model: model, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.headline)
                            .font(.title3.weight(.semibold))
                        Text(model.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Point(symbol: "menubar.arrow.up.rectangle", title: "Find Tuloy in the menu bar",
                  text: "Click its icon for the countdown, Ping Now, Pause, and to open this app's window again.")
            Point(symbol: "rectangle.inset.topright.filled", title: "Or keep the mini window open",
                  text: "A small panel that floats above everything. Closing it, or any Tuloy window, leaves Tuloy running.")
            Point(symbol: "iphone", title: "Mac asleep at ping time?",
                  text: "Tuloy pings as soon as it wakes. For a ping that never misses, Help shows how to set up your iPhone.")

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Notify me when a fresh window opens", isOn: $model.notify)
                    Toggle("Show the mini window when Tuloy starts", isOn: $model.miniAtLaunch)
                }
            }
        }
    }
}

/// An icon, a bold line, and a sentence or two.
struct Point: View {
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The dots that show where you are, with Back and Continue.
struct SetupFooter: View {
    var step: SetupStep
    var back: () -> Void
    var next: () -> Void

    var body: some View {
        HStack {
            Button("Back", action: back)
                .buttonStyle(TuloyButtonStyle())
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            HStack(spacing: 6) {
                ForEach(SetupStep.allCases, id: \.self) { each in
                    Circle()
                        .fill(each == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Button(step.nextTitle, action: next)
                .buttonStyle(TuloyButtonStyle(prominent: true))
        }
    }
}

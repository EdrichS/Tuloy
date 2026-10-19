import SwiftUI

/// The Schedule screen: when you want fresh windows, with a picture of the day that follows.
struct ScheduleScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                DatePicker("Fresh window at", selection: $model.freshTime, displayedComponents: .hourAndMinute)
                LabeledContent("On") {
                    WeekdayPicker(selection: $model.weekdays)
                }
                Toggle(isOn: $model.keepGoing) {
                    Text("Keep going")
                    Text("Start a new window each time one ends.")
                }
                .toggleStyle(.switch)
                if model.keepGoing {
                    DatePicker("Until", selection: $model.untilTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("When you want your allowance to refill")
            } footer: {
                Footer(model.schedule.summary)
            }

            Section {
                DayTimeline(schedule: model.schedule, now: model.now)
            } header: {
                Text("Your day")
            } footer: {
                Footer("The pale block is the early window Tuloy opens for you. Solid and dashed blocks are fresh ones. Mac asleep at ping time? Tuloy pings when it next wakes, which can be late. Help shows how to have your iPhone do it on time.")
            }
        }
        .formStyle(.grouped)
    }
}

/// The explanation under a group of settings. Left-aligned: macOS would push it to the right edge.
struct Footer: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Seven round buttons, one per day, in your region's order.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        // Calendar numbers days 1 (Sunday) to 7 (Saturday). Start from your region's first day.
        let days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }

        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[day - 1])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: 24, height: 24)
                        .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// The Preferences screen: how Tuloy looks and behaves.
struct PreferencesScreen: View {
    @Bindable var model: AppModel
    /// Whether the bottom of the screen is in view. Until it is, a cue says there's more below.
    @State private var seesBottom = false
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollViewReader { scroller in
            Form {
                Section {
                    DisplayModePicker(selection: $model.displayMode)
                } header: {
                    Text("Menu bar icon")
                } footer: {
                    Footer("A problem always shows Tuloy's symbol with \"!\", whatever you pick.")
                }

                Section {
                    Toggle(isOn: $model.checksUsage) {
                        Text("Check my usage every 5 minutes")
                        Text("Free: Claude Code reads your usage without sending Claude a message, so no tokens are used and no window starts.")
                    }
                    if let status = usageCheckStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(model.usageCheckCost != nil || model.usageCheckTrouble != nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                } header: {
                    Text("Usage")
                } footer: {
                    Footer("Keeps the ring, the week bar and the \"nearly out\" warnings current, and spots windows you started yourself, on any device.")
                }

                Section("Windows") {
                    Toggle(isOn: $model.openAtLaunch) {
                        Text("Show this window when I open Tuloy")
                        Text("It stays out of the way when Tuloy starts by itself at login.")
                    }
                    Toggle(isOn: $model.miniAtLaunch) {
                        Text("Show the mini window when Tuloy starts")
                        Text("The small panel that floats above your other windows.")
                    }
                }

                Section("Notifications") {
                    if model.wantsBlockedNotifications {
                        Blocked(text: "Notifications for Tuloy are off in System Settings, so none of these can show.",
                                button: "Open Notifications Settings", action: SystemNotices.openSettings)
                    }
                    Toggle("Tell me when a fresh window opens", isOn: $model.notify)
                    Toggle(isOn: $model.warnNearlyOut) {
                        Text("Warn me when a window is nearly used up")
                        Text("At 80% and at 95%, with the time left until it resets.")
                    }
                    Toggle(isOn: $model.warnWeek) {
                        Text("Warn me when my week is nearly used up")
                        Text("At 80% and at 95% of your weekly allowance.")
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { model.loginItem == .on || model.loginItem == .needsApproval },
                                         set: { model.setLaunchAtLogin($0) })) {
                        Text("Launch at login")
                        Text("Tuloy has to be running to ping. It must be in your Applications folder for this.")
                    }
                    .disabled(Demo.isOn)
                    switch model.loginItem {
                    case .needsApproval:
                        Blocked(text: "macOS is holding this back until you allow Tuloy in System Settings, under Login Items.",
                                button: "Open Login Items", action: LoginItem.openSettings)
                    case .notFound:
                        Blocked(text: "macOS can't add this copy of Tuloy. Move Tuloy to your Applications folder, open it from there, and try again.",
                                button: nil, action: {})
                    case .on, .off:
                        EmptyView()
                    }
                } header: {
                    Text("General")
                } footer: {
                    Color.clear.frame(height: 1)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: BottomEdge.self, value: proxy.frame(in: .named(Self.space)).minY)
                        })
                        .id(Self.bottom)
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .coordinateSpace(name: Self.space)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { height = proxy.size.height }.onChange(of: proxy.size.height) { _, new in height = new }
            })
            .onPreferenceChange(BottomEdge.self) { bottom in
                seesBottom = bottom.map { $0 <= height - 8 } ?? false
            }
            .overlay(alignment: .bottom) {
                if !seesBottom {
                    MoreBelow { withAnimation { scroller.scrollTo(Self.bottom, anchor: .bottom) } }
                }
            }
        }
        .task { await model.refreshPermissions() }
    }

    private static let space = "preferences"
    private static let bottom = "bottom"

    private var usageCheckStatus: String? {
        if let cost = model.usageCheckCost {
            return "Stopped: one check used \(cost) tokens when it should have used none. Switch this on to try again."
        }
        if let trouble = model.usageCheckTrouble { return "Last check didn't work: \(trouble)" }
        if let checked = model.usageCheckedAt { return "Last checked \(Format.age(of: checked, now: model.now))." }
        return nil
    }
}

/// Where the bottom of a scrolling screen is, in that screen's own coordinates.
private struct BottomEdge: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

/// A fade and a small button at the bottom edge, while there's more to scroll to.
struct MoreBelow: View {
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
                .allowsHitTesting(false)
            Button(action: action) {
                Label("More below", systemImage: "chevron.down")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(TuloyButtonStyle())
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .transition(.opacity)
    }
}

/// Something macOS is holding back, in orange, with the way to fix it.
struct Blocked: View {
    var text: String
    var button: String?
    var action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                if let button {
                    Button(button, action: action)
                        .buttonStyle(TuloyButtonStyle())
                }
            }
        }
        .font(.callout)
    }
}

/// The four looks, each with a sample of what you'd see in the menu bar.
struct DisplayModePicker: View {
    @Binding var selection: DisplayMode

    var body: some View {
        ForEach(DisplayMode.allCases) { mode in
            Button {
                selection = mode
            } label: {
                HStack(spacing: 12) {
                    sample(of: mode)
                        .frame(width: 40, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.label)
                        Text(mode.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .opacity(selection == mode ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == mode ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func sample(of mode: DisplayMode) -> some View {
        switch mode {
        case .classic:
            Glyph(status: .running)
        case .usage:
            Image(nsImage: Ring(progress: 0.62, text: "62").image()).renderingMode(.template)
        case .timer:
            Text("3:41").font(.system(size: 13)).monospacedDigit()
        case .ultra:
            Image(nsImage: Ring(progress: 0.62, text: "4h").image()).renderingMode(.template)
        }
    }
}

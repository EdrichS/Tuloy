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
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                DisplayModePicker(selection: $model.displayMode)
            } header: {
                Text("Menu bar icon")
            } footer: {
                Footer("A problem always shows ⚠, whatever you pick. The ring shows a percentage once Claude Code reports one.")
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

            Section("General") {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login")
                    Text("Tuloy has to be running to ping. It must be in your Applications folder for this.")
                }
                .onChange(of: launchAtLogin) { _, isOn in LoginItem.set(isOn) }
                .disabled(Demo.isOn)
            }
        }
        .formStyle(.grouped)
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
            Image(systemName: "checkmark.circle").font(.system(size: 15))
        case .usage:
            Image(nsImage: Ring(progress: 0.62, text: "62").image()).renderingMode(.template)
        case .timer:
            Text("3:41").font(.system(size: 13)).monospacedDigit()
        case .ultra:
            Image(nsImage: Ring(progress: 0.62, text: "3:41").image()).renderingMode(.template)
        }
    }
}

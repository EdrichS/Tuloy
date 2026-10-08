import SwiftUI

/// The main window: one place to see what Tuloy is doing and set everything up.
/// Open it from the menu bar ("Open Tuloy…") or by opening the app again.
struct MainWindow: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            Divider()
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 700, height: 560)
    }

    @ViewBuilder
    private var screen: some View {
        switch model.mainTab {
        case .home:
            ScrollView { HomeContent(model: model).padding(20) }
        case .schedule:
            ScheduleScreen(model: model)
        case .connection:
            ScrollView { ConnectionContent(model: model).padding(20) }
        case .preferences:
            PreferencesScreen(model: model)
        case .help:
            ScrollView { HelpContent(model: model).padding(20) }
        }
    }
}

/// The list of screens down the left side.
struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Demo.isOn ? "Tuloy (demo)" : "Tuloy")
                    .font(.title3.weight(.bold))
                Text("\u{201C}Keep going\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            ForEach(MainTab.allCases) { tab in
                Button {
                    model.mainTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbol)
                            .frame(width: 18)
                        Text(tab.title)
                        Spacer()
                        // A dot on Connection whenever something there needs you.
                        if tab == .connection, model.attention != nil {
                            Circle().fill(.orange).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(model.mainTab == tab ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background(model.mainTab == tab ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.mainTab == tab ? .isSelected : [])
            }

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(width: 176)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    private var statusText: String {
        switch model.status {
        case .running: return "Running"
        case .paused: return "Paused"
        case .resting: return "Resting"
        case .problem: return "Needs attention"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .running: return .green
        case .paused, .resting: return .gray
        case .problem: return .orange
        }
    }
}

// MARK: - Home

/// Where things stand, the things you can do, and what Tuloy did lately.
struct HomeContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                HStack(spacing: 16) {
                    StatusRing(model: model)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.headline)
                            .font(.title2.weight(.semibold))
                        Text(model.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.attention != nil {
                            Button("Fix It in Connection") { model.mainTab = .connection }
                                .buttonStyle(TuloyButtonStyle(prominent: true))
                                .padding(.top, 4)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                ActionTile(title: model.isPinging ? "Pinging…" : "Ping Now", symbol: "paperplane.fill",
                           caption: "Start a window this minute.") {
                    Task { await model.pingNow() }
                }
                .disabled(model.isPinging)

                ActionTile(title: model.isPaused ? "Resume" : "Pause", symbol: model.isPaused ? "play.fill" : "pause.fill",
                           caption: model.isPaused ? "Start pinging again." : "No pings until you resume.") {
                    model.togglePause()
                }

                ActionTile(title: "Mini Window", symbol: "rectangle.inset.topright.filled",
                           caption: "Small, and always on top.") {
                    model.open(.mini)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Fact(title: "Next ping", value: model.upcomingPing.map(Format.time) ?? "None planned",
                     caption: "Tuloy's next message.")
                Fact(title: "This window", value: model.usagePercent.map { "\($0)% used" } ?? "Not reported",
                     caption: "Your 5-hour allowance.")
                Fact(title: "This week", value: model.currentWeek?.percent.map { "\($0)% used" } ?? "Not reported",
                     caption: "Your weekly allowance.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent pings")
                    .font(.headline)
                if model.history.isEmpty {
                    Text("No pings yet. Each ping Tuloy sends shows up here, with what came back.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.history.prefix(5), id: \.date) { ping in
                    HStack(spacing: 8) {
                        Image(systemName: ping.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ping.ok ? .green : .orange)
                        Text(Format.time(ping.date))
                            .monospacedDigit()
                            .frame(width: 92, alignment: .leading)
                        Text(ping.kindText)
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Text(ping.outcomeText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let tokens = ping.tokens {
                            Text("\(tokens) tokens")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// A button that says what it does.
private struct ActionTile: View {
    var title: String
    var symbol: String
    var caption: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}

/// One number with a name and a few words about what it is.
private struct Fact: View {
    var title: String
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

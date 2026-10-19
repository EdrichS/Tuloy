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
        case .history:
            ScrollView { HistoryContent(model: model).padding(20) }
        case .schedule:
            ScheduleScreen(model: model)
        case .messages:
            ScrollView { MessagesContent(model: model).padding(20) }
        case .connection:
            ScrollView { ConnectionContent(model: model).padding(20) }
        case .preferences:
            PreferencesScreen(model: model)
        case .help:
            ScrollView { HelpContent(model: model).padding(20) }
        case .about:
            ScrollView { AboutContent(model: model).padding(20) }
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
                        // A spinner on Messages while Claude is working on one.
                        if tab == .messages, model.sendingMessage != nil {
                            ProgressView().controlSize(.mini)
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

/// Where things stand, today as it actually went, and what Tuloy did lately.
struct HomeContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                PanelContent(model: model, place: .home)
            }

            if model.wantsBlockedNotifications {
                Blocked(text: "Notifications for Tuloy are off in System Settings, so you won't hear when a fresh window opens or you're nearly out.",
                        button: "Open Notifications Settings", action: SystemNotices.openSettings)
            }
            if model.loginItem == .needsApproval {
                Blocked(text: "Launch at login is on, but macOS is holding it back until you allow Tuloy in System Settings, under Login Items.",
                        button: "Open Login Items", action: LoginItem.openSettings)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .font(.headline)
                Card {
                    TodayTimeline(windows: model.windows, toCome: model.windowsToCome, now: model.now, calendar: model.calendar)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent pings")
                        .font(.headline)
                    Spacer()
                    if !model.history.isEmpty {
                        Button("See All in History") { model.mainTab = .history }
                            .buttonStyle(TuloyButtonStyle())
                    }
                }
                if model.history.isEmpty {
                    Text("No pings yet. Each ping Tuloy sends shows up here, with what came back.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.history.prefix(5), id: \.date) { ping in
                    PingRow(ping: ping)
                }
            }
        }
    }
}

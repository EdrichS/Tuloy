import AppKit
import SwiftUI

/// The panel: where things stand, and the two things you can do about it.
///
/// One design, used three times: under the menu bar icon, as the mini window,
/// and at the top of Home. Change it here and it changes everywhere.
struct PanelContent: View {
    let model: AppModel
    var place = Place.popover

    enum Place { case popover, mini, home }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StatusRing(model: model, size: place == .home ? 92 : 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place == .home ? model.headline : shortHeadline)
                        .font(place == .home ? .title2.weight(.semibold) : .callout.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(place == .home ? model.detail : shortDetail)
                        .font(place == .home ? .body : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let age {
                        HStack(spacing: 4) {
                            Text(age)
                            Button {
                                Task { await model.refreshUsage() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isPinging)
                            .help("Refresh now. This sends one ping (about \(model.lastPing?.tokens ?? 350) tokens).")
                            .accessibilityLabel("Refresh usage")
                        }
                        .font(.caption)
                        .foregroundStyle(model.isUsageStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    }
                }
                Spacer(minLength: 0)
            }

            if let note = model.currentPlanNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.isResting, let week = model.currentWeek, let percent = week.percent {
                WeekBar(percent: percent, resets: Format.when(week.resetsAt, now: model.now))
            }

            HStack(spacing: 6) {
                if model.attention != nil {
                    // Pinging won't work until this is fixed, so lead with the fix.
                    Button("Fix It…") { go(.main, .connection) }
                        .buttonStyle(TuloyButtonStyle(prominent: true))
                        .help("Open Connection to see what's wrong")
                }
                pingButton
                Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                    .buttonStyle(TuloyButtonStyle())
                    .help(model.isPaused ? "Start pinging again" : "No pings until you resume")

                Spacer(minLength: 0)

                if place == .mini {
                    Button {
                        go(.main, model.attention == nil ? .home : .connection)
                    } label: {
                        Image(systemName: "macwindow")
                    }
                    .buttonStyle(TuloyButtonStyle())
                    .help("Open the Tuloy window")
                    .accessibilityLabel("Open the Tuloy window")
                } else if place == .home {
                    Button("Mini Window") { model.open(.mini) }
                        .buttonStyle(TuloyButtonStyle())
                        .help("A small panel that stays on top of everything")
                }
            }

            Text(model.forecast.sentence(now: model.now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NoticeLine(model: model)
        }
    }

    /// No keyboard shortcut on purpose: a ping spends tokens and can start a window,
    /// so it should take a deliberate click.
    private var pingButton: some View {
        Button(model.isPinging ? "Pinging…" : "Ping Now") {
            Task { await model.pingNow() }
        }
        // While resting or waiting on a fix, a ping can't help, so it isn't the bright button.
        .buttonStyle(TuloyButtonStyle(prominent: model.status == .running))
        .disabled(model.isPinging)
        .help(model.currentWindow == nil
              ? "Starts a new 5-hour window right now"
              : "Sends one ping. Your window is already open, so this only refreshes your usage")
    }

    private func go(_ window: WindowID, _ tab: MainTab) {
        model.open(window, tab: tab)
        if place == .popover { Popover.close() }
    }

    /// The window that's open, if things are running normally.
    private var openWindow: UsageReading? {
        model.status == .running ? model.currentWindow : nil
    }

    /// Shorter than Home's line, to fit a small panel.
    private var shortHeadline: String {
        guard let openWindow else { return model.headline }
        return "Fresh at \(openWindow.isEstimate ? "about " : "")\(Format.time(openWindow.resetsAt))"
    }

    private var shortDetail: String {
        guard let openWindow else { return model.detail }
        return "Resets in \(Format.duration(to: openWindow.resetsAt, from: model.now))"
    }

    /// How old the usage figure is. Only shown when there is a figure.
    private var age: String? {
        guard let openWindow, openWindow.percent != nil else { return nil }
        return "Usage \(Format.age(of: openWindow.asOf, now: model.now))"
    }
}

/// Your weekly allowance as a bar.
struct WeekBar: View {
    var percent: Int
    var resets: String

    var body: some View {
        HStack(spacing: 8) {
            Text("This week")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(percent >= 80 ? Color.orange : Color.accentColor)
                        .frame(width: max(4, proxy.size.width * CGFloat(min(percent, 100)) / 100))
                }
            }
            .frame(height: 6)
            Text("\(percent)%")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Your weekly allowance. It resets \(resets).")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(percent)% used. Resets \(resets).")
    }
}

/// One line saying what just happened. It goes away by itself after a few seconds.
struct NoticeLine: View {
    let model: AppModel

    var body: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: notice.isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(notice.isGood ? .green : .orange)
                Text(notice.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .task(id: notice) {
                try? await Task.sleep(for: .seconds(8))
                model.dismissNotice(notice)
            }
        }
    }
}

// MARK: - Under the menu bar icon

/// The panel that opens when you click Tuloy's menu bar icon.
struct PopoverView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelContent(model: model, place: .popover)

            Divider()

            HStack(spacing: 6) {
                Button("Open Tuloy") {
                    model.open(.main, tab: .home)
                    Popover.close()
                }
                .buttonStyle(TuloyButtonStyle())

                Button("Mini Window") {
                    model.open(.mini)
                    Popover.close()
                }
                .buttonStyle(TuloyButtonStyle())

                Spacer(minLength: 0)
                MoreMenu(model: model)
            }
        }
        .padding(14)
        .frame(width: 310)
        // Escape closes the panel.
        .background {
            Button("Close") { Popover.close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .background(WindowConfigurator { Popover.window = $0 })
    }
}

/// The panel's own window, kept so that buttons inside it can close it.
@MainActor
enum Popover {
    static weak var window: NSWindow?

    /// Closes the panel the same way a click on the menu bar icon does. (Closing the window
    /// directly leaves macOS thinking it's still open, and the next click then does nothing.)
    static func close() {
        guard window?.isVisible == true else { return }
        NSApp.windows.lazy.compactMap { statusButton(in: $0.contentView) }.first?.performClick(nil)
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { statusButton(in: $0) }.first
    }
}

/// The "…" button: everything that isn't needed every time.
struct MoreMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            Button("Settings…") { go(.schedule) }
                .keyboardShortcut(",")
            Button("Connection…") { go(.connection) }
            Button("Help") { go(.help) }

            Menu("Recent Pings") {
                if model.history.isEmpty {
                    Text("No pings yet")
                }
                ForEach(model.history, id: \.date) { ping in
                    Text(line(for: ping))
                }
            }

            if Demo.isOn {
                Menu("Demo Scene") {
                    ForEach(Demo.Scene.allCases) { scene in
                        Button(scene.rawValue) { model.show(scene) }
                    }
                }
            }

            Divider()

            Button("Quit Tuloy") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings, Help, recent pings, and Quit")
        .accessibilityLabel("More")
    }

    private func go(_ tab: MainTab) {
        model.open(.main, tab: tab)
        Popover.close()
    }

    /// "✓ Tue 6:00 AM · Scheduled · Fresh at 11:00 AM · 350 tokens"
    private func line(for ping: PingRecord) -> String {
        let cost = ping.tokens.map { "\($0) tokens" }
        return ["\(ping.mark) \(Format.time(ping.date))", ping.kindText, ping.outcomeText, cost]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Today, as it actually went

/// Today's windows on one bar: the ones that opened, where you are now, and what's still to come.
///
/// Filled blocks are windows so far, filled as high as your usage got. Outlined blocks are planned.
struct TodayTimeline: View {
    var windows: [WindowRecord]
    var toCome: [DateInterval]
    var now: Date
    var calendar: Calendar = .current

    @State private var selected: WindowRecord?

    private let barTop: CGFloat = 14
    private let barHeight: CGFloat = 26

    var body: some View {
        let day = DateInterval(start: calendar.startOfDay(for: now), duration: 24 * 60 * 60)
        let today = windows.filter { $0.end > day.start && $0.start < day.end }

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                chart(today, day: day, width: proxy.size.width)
            }
            .frame(height: barTop + barHeight + 18)

            Text(caption(for: selected, count: today.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func chart(_ today: [WindowRecord], day: DateInterval, width: CGFloat) -> some View {
        let x = { (date: Date) -> CGFloat in
            width * min(1, max(0, date.timeIntervalSince(day.start) / day.duration))
        }

        return ZStack(alignment: .topLeading) {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(day.start.addingTimeInterval(TimeInterval(hour) * 3600).formatted(.dateTime.hour()))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .offset(x: width * CGFloat(hour) / 24)
            }

            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: width, height: barHeight)
                .offset(y: barTop)

            // Still to come: outlined.
            ForEach(toCome, id: \.start) { window in
                let start = x(window.start), end = x(window.end)
                if end - start > 3 {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: end - start - 2, height: barHeight)
                        .offset(x: start + 1, y: barTop)
                }
            }

            // So far: filled as high as usage got.
            ForEach(today, id: \.end) { window in
                let start = x(window.start), end = x(window.end)
                if end - start > 3 {
                    Button {
                        selected = selected == window ? nil : window
                    } label: {
                        block(for: window, width: end - start - 2)
                    }
                    .buttonStyle(.plain)
                    .offset(x: start + 1, y: barTop)
                    .help(details(for: window))
                }
            }

            Capsule()
                .fill(.primary)
                .frame(width: 2, height: barHeight + 8)
                .offset(x: x(now) - 1, y: barTop - 4)

            ForEach(today, id: \.end) { window in
                if window.start >= day.start {
                    label(time(window.start), at: x(window.start), width: width)
                }
            }
            ForEach(toCome, id: \.start) { window in
                label(time(window.start), at: x(window.start), width: width)
            }
        }
    }

    /// A window so far: pale, with a darker fill rising to the highest usage seen in it.
    private func block(for window: WindowRecord, width: CGFloat) -> some View {
        let tint: Color = window.openedBy == .tuloy ? .accentColor : .teal
        let fill = CGFloat(min(max(window.peak ?? 0, 0), 100)) / 100
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.3))
            Rectangle().fill(tint.opacity(0.9)).frame(height: barHeight * fill)
        }
        .frame(width: max(0, width), height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            if selected == window {
                RoundedRectangle(cornerRadius: 5).strokeBorder(.primary, lineWidth: 1.5)
            }
        }
    }

    private func label(_ text: String, at x: CGFloat, width: CGFloat) -> some View {
        let box: CGFloat = 60
        return Text(text)
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: box, alignment: .leading)
            .offset(x: min(max(0, x), max(0, width - box)), y: barTop + barHeight + 4)
    }

    private func caption(for selected: WindowRecord?, count: Int) -> String {
        if let selected { return details(for: selected) }
        if count == 0, toCome.isEmpty { return "No windows today yet." }
        return "Filled: windows so far, as high as your usage got. Dashed: still to come. Click one for details."
    }

    private func details(for window: WindowRecord) -> String {
        let who = window.openedBy == .tuloy ? "opened by Tuloy" : "already open when Tuloy looked (your own use, or your phone)"
        let peak = window.peak.map { "highest usage \($0)%" } ?? "usage not reported"
        return "\(time(window.start)) to \(time(window.end)): \(who), \(peak)."
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

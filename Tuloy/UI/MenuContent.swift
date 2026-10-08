import AppKit
import SwiftUI

/// The dropdown menu.
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(Demo.isOn ? "Tuloy (demo)" : "Tuloy")
        Text(freshLine)
        if let windowLine {
            Text(windowLine)
        }
        if let weekLine {
            Text(weekLine)
        }
        if let nextPingLine {
            Text(nextPingLine)
        }
        Text(lastPingLine)
        if let attention = model.attention {
            Text("⚠ \(attention.errorDescription ?? "Something went wrong.")")
            if let fix = attention.recoverySuggestion {
                Text(fix)
            }
        }

        Divider()

        Button("Open Tuloy…") {
            model.open(.main, tab: .home)
        }
        .keyboardShortcut("o")
        if model.attention != nil {
            Button("Fix This…") {
                model.open(.main, tab: .connection)
            }
        }
        Button("Show Mini Window") {
            model.open(.mini)
        }

        Divider()

        Button(model.isPaused ? "Resume" : "Pause") {
            model.togglePause()
        }
        Button(model.isPinging ? "Pinging…" : "Ping Now") {
            Task { await model.pingNow() }
        }
        .disabled(model.isPinging)

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

        Button("Settings…") {
            model.open(.main, tab: .schedule)
        }
        .keyboardShortcut(",")
        Button("Help") {
            model.open(.main, tab: .help)
        }

        Button("Quit Tuloy") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var freshLine: String {
        if model.isResting, let week = model.currentWeek {
            return "Weekly limit used up · resets \(Format.time(week.resetsAt))"
        }
        guard let freshAt = model.freshAt else { return "No fresh window scheduled" }
        let about = model.currentWindow?.isEstimate == true ? "about " : ""
        return "Fresh window at \(about)\(Format.time(freshAt)) · in \(Format.countdown(to: freshAt, from: model.now))"
    }

    private var windowLine: String? {
        guard let percent = model.usagePercent, let window = model.currentWindow else { return nil }
        return "This window: \(percent)% used · as of \(Format.time(window.asOf))"
    }

    private var weekLine: String? {
        guard !model.isResting, let week = model.currentWeek, let percent = week.percent else { return nil }
        return "This week: \(percent)% used · resets \(Format.time(week.resetsAt))"
    }

    private var nextPingLine: String? {
        guard let next = model.upcomingPing, next > model.now else { return nil }
        return "Next ping \(Format.time(next))"
    }

    private var lastPingLine: String {
        guard let last = model.lastPing else { return "No pings yet" }
        return "Last ping \(Format.time(last.date)) \(last.ok ? "✓" : "✕")"
    }

    /// "✓ Tue 6:00 AM · scheduled · fresh at 11:00 AM · 38 tokens" or "✕ 6:00 AM · scheduled · Claude Code is signed out."
    private func line(for ping: PingRecord) -> String {
        let why: String
        switch ping.kind {
        case .scheduled: why = "scheduled"
        case .keepGoing: why = "keep going"
        case .manual: why = "by you"
        }
        let outcome = ping.note ?? ping.resetsAt.map { "fresh at \(Format.time($0))" }
        let cost = ping.tokens.map { "\($0) tokens" }
        return ["\(ping.ok ? "✓" : "✕") \(Format.time(ping.date))", why, outcome, cost].compactMap { $0 }.joined(separator: " · ")
    }
}

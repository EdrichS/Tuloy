import AppKit
import SwiftUI

/// The four ways Tuloy can look in your menu bar.
enum DisplayMode: String, CaseIterable, Identifiable {
    case classic, usage, timer, ultra

    var id: Self { self }
    var label: String { rawValue.capitalized }

    var summary: String {
        switch self {
        case .classic: return "A simple icon: running, paused, or needs attention."
        case .usage: return "A ring that fills as you use your 5-hour allowance."
        case .timer: return "A countdown to your next fresh window."
        case .ultra: return "The usage ring, with the countdown inside."
        }
    }

    var showsUsage: Bool { self == .usage || self == .ultra }
}

/// What you see in the menu bar.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        icon
            .accessibilityLabel(accessibilityText)
            // Only a view can open a window, and this one is always here. So when anything
            // asks for a window (the menu, another window, starting up), it's opened from here.
            .onChange(of: model.windowRequests, initial: true) { _, requests in
                guard !requests.isEmpty else { return }
                model.windowRequests = []
                NSApp.activate()   // menu bar apps start in the background; bring the window to the front
                for window in requests {
                    openWindow(id: window.rawValue)
                }
            }
            // Read out what just happened, for people using VoiceOver.
            .onChange(of: model.notice) { _, notice in
                if let notice { AccessibilityNotification.Announcement(notice.text).post() }
            }
    }

    @ViewBuilder
    private var icon: some View {
        // A problem always wins, whatever the mode, so you never miss one.
        if model.status == .problem {
            Image(systemName: "exclamationmark.triangle")
        } else {
            switch model.displayMode {
            case .classic:
                statusIcon
            case .usage:
                Image(nsImage: Ring(progress: usageProgress, text: usageText, isFaded: model.isUsageStale).image())
            case .timer:
                if model.freshAt != nil { Text(countdown) } else { statusIcon }
            case .ultra:
                Image(nsImage: Ring(progress: usageProgress, text: countdown, isFaded: model.isUsageStale).image())
            }
        }
    }

    private var statusIcon: Image {
        switch model.status {
        case .paused: return Image(systemName: "pause.circle")
        case .resting: return Image(systemName: "moon.zzz")
        case .running, .problem: return Image(systemName: "checkmark.circle")
        }
    }

    private var usageProgress: Double { Double(model.usagePercent ?? 0) / 100 }
    private var usageText: String { model.usagePercent.map { "\($0)" } ?? "–" }
    private var countdown: String { Format.countdown(to: model.freshAt, from: model.now) }

    private var accessibilityText: String {
        if let attention = model.attention { return "Tuloy: \(attention.errorDescription ?? "needs attention")" }
        guard let freshAt = model.freshAt else { return model.isPaused ? "Tuloy, paused" : "Tuloy" }
        return "Tuloy: fresh window at \(Format.time(freshAt))"
    }
}

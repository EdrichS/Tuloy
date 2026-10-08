import Foundation
import ServiceManagement
import UserNotifications

/// Tuloy's notifications: "fresh window", and a heads-up when pings need your help.
enum Notifier {
    private static let freshID = "fresh-window"
    private static let problemID = "problem"

    /// Notifications need a real app, so not when Tuloy runs bare (`swift run`). Demo mode stays quiet too.
    private static let isAvailable = Bundle.main.bundleIdentifier != nil && !Demo.isOn

    static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Schedules the fresh window notification for `date`, replacing any earlier one.
    static func freshWindow(at date: Date) {
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        send(id: freshID, title: "Fresh window", body: "Your Claude usage just reset.",
             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
    }

    static func cancelFreshWindow() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [freshID])
    }

    /// Tells you right away when pings can't work until you step in.
    static func problem(_ error: PingError) {
        send(id: problemID, title: error.errorDescription ?? "Tuloy needs attention",
             body: error.recoverySuggestion ?? "Open Tuloy in the menu bar for details.", trigger: nil)
    }

    private static func send(id: String, title: String, body: String, trigger: UNNotificationTrigger?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// "Launch at login", using macOS's built-in login items.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Tuloy couldn't change launch at login: \(error.localizedDescription)")
        }
    }
}

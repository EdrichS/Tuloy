import Foundation
import ServiceManagement
import UserNotifications

/// The real notifications socket: macOS's Notification Centre.
final class SystemNotices: Notices {
    private let freshID = "fresh-window"

    /// Notifications need a real app, so not when Tuloy runs bare (`swift run`).
    private let isAvailable = Bundle.main.bundleIdentifier != nil

    func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func freshWindow(at date: Date?) {
        guard isAvailable else { return }
        guard let date else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [freshID])
            return
        }
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        send(freshID, title: "Fresh window", body: "Your Claude usage just reset.",
             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
    }

    func post(_ id: String, title: String, body: String) {
        send(id, title: title, body: body, trigger: nil)
    }

    private func send(_ id: String, title: String, body: String, trigger: UNNotificationTrigger?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Notifications that go nowhere. For demo mode.
final class SilentNotices: Notices {
    func requestPermission() {}
    func freshWindow(at date: Date?) {}
    func post(_ id: String, title: String, body: String) {}
}

/// The real storage socket: the app's saved preferences.
final class PreferencesStorage: Storage {
    func value(for key: String) -> Any? { UserDefaults.standard.object(forKey: key) }
    func set(_ value: Any?, for key: String) { UserDefaults.standard.set(value, forKey: key) }
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

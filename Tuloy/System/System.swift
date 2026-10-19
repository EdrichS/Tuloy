import AppKit
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

    /// True when you've turned Tuloy's notifications off in System Settings.
    static func areBlocked() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// System Settings, at Tuloy's notifications.
    static func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.edrichsilva.tuloy"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
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
    enum State: Equatable {
        case on, off
        /// Switched on, but held back in System Settings until you allow it.
        case needsApproval
        /// macOS can't find this copy of Tuloy to register, usually because it isn't in Applications.
        case notFound
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notFound: return .notFound
        default: return .off
        }
    }

    static var isEnabled: Bool { state == .on || state == .needsApproval }

    /// System Settings, at Login Items.
    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Tuloy couldn't change launch at login: \(error.localizedDescription)")
        }
    }
}

/// Makes sure only one real Tuloy runs at a time. Two would both ping, on the same schedule.
enum OnlyCopy {
    /// Takes the lock file, or returns nil if another Tuloy already holds it. The lock is held for as
    /// long as the returned file stays open, and macOS lets go of it when Tuloy quits, however it quits.
    static func claim(at url: URL) -> Int32? {
        let file = open(url.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        guard file >= 0 else { return -1 }   // can't tell either way: don't stop Tuloy starting
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            close(file)
            return nil
        }
        return file
    }
}

import AppKit
import SwiftUI

/// Tuloy ("keep going" in Filipino) starts your Claude usage window on a
/// schedule, so your 5-hour allowance resets when you want it to.
@main
struct TuloyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        // Tuloy lives in the menu bar: no Dock icon (LSUIElement in Support/Info.plist).
        // This is the one piece that's always there. It also opens the windows below.
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        // The windows. Closing any of them leaves Tuloy running in the menu bar.
        Window("Tuloy", id: WindowID.main.rawValue) {
            MainWindow(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome to Tuloy", id: WindowID.setup.rawValue) {
            SetupWindow(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Tuloy Mini", id: WindowID.mini.rawValue) {
            MiniWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Window("Connect Tuloy to Claude", id: WindowID.guide.rawValue) {
            ScrollView {
                GuideContent(model: model)
                    .padding(20)
            }
            .frame(width: 440, height: 620)
            .floatingWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.trailing)
    }
}

/// The parts of starting up that SwiftUI doesn't cover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Tuloy decides which windows to show when it starts. Don't let macOS reopen old ones.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS says when an app was started by "launch at login" and not by you.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        AppModel.shared.didLaunch(atLogin: atLogin)
    }

    /// Opening Tuloy again while it's running (from Finder, Spotlight or Launchpad) shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppModel.shared.open(.main)
        return true
    }

    /// Closing the last window must not quit: the menu bar item is the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

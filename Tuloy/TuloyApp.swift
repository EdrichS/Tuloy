import AppKit
import SwiftUI

/// Tuloy ("keep going" in Filipino) starts your Claude usage window on a
/// schedule, so your 5-hour allowance resets when you want it to.
@main
struct TuloyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        // Tuloy lives in the menu bar (LSUIElement in Support/Info.plist), and shows in the Dock
        // only while one of its windows is open. This is the one piece that's always there.
        // It also opens the windows below.
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        // The windows. Closing any of them leaves Tuloy running in the menu bar.
        Window("Tuloy", id: WindowID.main.rawValue) {
            MainWindow(model: model)
                .tracksWindow(.main, model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { TuloyCommands(model: model) }

        Window("Welcome to Tuloy", id: WindowID.setup.rawValue) {
            SetupWindow(model: model)
                .tracksWindow(.setup, model: model)
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
            .tracksWindow(.guide, model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.trailing)
    }
}

/// The menu bar Tuloy has while it's in the Dock. SwiftUI supplies the standard menus,
/// Edit among them (so Command-C and Command-V work in every window); these fit them to Tuloy.
struct TuloyCommands: SwiftUI.Commands {
    let model: AppModel

    var body: some SwiftUI.Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Tuloy") { model.open(.main, tab: .about) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.open(.main, tab: .preferences) }
                .keyboardShortcut(",")
        }
        // SwiftUI gives Tuloy no File menu, and so no Command-W. This puts it back.
        CommandGroup(replacing: .saveItem) {
            Button("Close Window") {
                guard let window = NSApp.keyWindow else { return }
                if window === Popover.window {
                    Popover.close()   // the panel has its own way of closing (Panel.swift)
                } else if window.styleMask.contains(.closable) {
                    window.performClose(nil)
                } else {
                    window.close()   // the mini window has no close button to press
                }
            }
            .keyboardShortcut("w")
        }
        // The View menu: each screen of the main window, Command-1 to Command-8.
        CommandGroup(before: .sidebar) {
            ForEach(Array(MainTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.open(.main, tab: tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandGroup(replacing: .help) {
            Button("Tuloy Help") { model.open(.main, tab: .help) }
        }
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

    /// A message Claude is still working on is stopped, not left running with nobody watching.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopSending()
    }

    /// Closing the last window must not quit: the menu bar item is the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

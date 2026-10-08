import AppKit
import SwiftUI
import Testing
@testable import Tuloy

/// Draws Tuloy's custom views to make sure they render.
///
/// To look at them, set a folder and they're saved there as PNGs:
///   TULOY_SNAPSHOTS=/tmp/tuloy swift test --filter ViewTests
@MainActor
@Suite struct ViewTests {

    @Test func ringRenders() throws {
        let image = Ring(progress: 0.62, text: "62").image()
        #expect(image.size == CGSize(width: 20, height: 20))
        #expect(image.isTemplate)

        try save(Ring(progress: 0.62, text: "62").scaleEffect(4).frame(width: 96, height: 96), as: "ring-usage")
        try save(Ring(progress: 0.3, text: "3:41").scaleEffect(4).frame(width: 96, height: 96), as: "ring-ultra")
        try save(Ring(progress: 1, text: "100").scaleEffect(4).frame(width: 96, height: 96), as: "ring-full")
        try save(Ring(progress: 0.8, text: "45m").scaleEffect(4).frame(width: 96, height: 96), as: "ring-minutes")
    }

    @Test func timelineRenders() throws {
        var schedule = Schedule()
        try save(DayTimeline(schedule: schedule, now: october(5, 9), calendar: calendar), as: "timeline")

        schedule.keepGoing = true
        try save(DayTimeline(schedule: schedule, now: october(5, 9), calendar: calendar), as: "timeline-keep-going")

        schedule.freshMinutes = 2 * 60
        try save(DayTimeline(schedule: schedule, now: october(5, 9), calendar: calendar), as: "timeline-early")
    }

    @Test func pickersRender() throws {
        try save(WeekdayPicker(selection: .constant([2, 3, 4, 5, 6])), as: "weekdays")
        try save(VStack(spacing: 10) { DisplayModePicker(selection: .constant(.usage)) }, as: "display-modes")
    }

    // MARK: - The windows
    //
    // Tests always run with made-up data (see Demo.swift), so the shared model is safe to use.

    private var model: AppModel { AppModel.shared }

    @Test func testsNeverUseTheRealThing() {
        // If this fails, a test could send a real ping or change real settings. Fix Demo.isOn first.
        #expect(Demo.isOn)
        #expect(model.claudePath == "~/.local/bin/claude")   // the made-up path, not one found on this Mac
    }

    @Test func mainWindowRenders() throws {
        for (scene, name) in [(Demo.Scene.running, "home"), (.waiting, "home-waiting"), (.problem, "home-problem")] {
            model.show(scene)
            model.mainTab = .home
            try save(window(HomeContent(model: model)), as: "main-\(name)", width: 700)
        }
    }

    @Test func connectionScreenRenders() throws {
        model.show(.problem)   // signed out: the step most people are missing
        model.mainTab = .connection
        try save(window(ConnectionContent(model: model)), as: "main-connection-signed-out", width: 700)

        model.show(.running)
        try save(window(ConnectionContent(model: model)), as: "main-connection-ready", width: 700)
        try save(GuideContent(model: model).padding(20), as: "guide", width: 440)
    }

    @Test func helpRenders() throws {
        model.show(.running)
        model.mainTab = .help
        try save(window(HelpContent(model: model)), as: "main-help", width: 700)
        try save(QuestionRow(question: Question.all[1], isOpen: true), as: "help-question", width: 480)
    }

    @Test func welcomeRenders() throws {
        model.show(.problem)
        for step in SetupStep.allCases {
            let page = VStack(spacing: 0) {
                SetupPage(model: model, step: step).padding(24)
                Divider()
                SetupFooter(step: step, back: {}, next: {}).padding(.horizontal, 20).padding(.vertical, 12)
            }
            try save(page, as: "welcome-\(step.rawValue + 1)-\(step)", width: 560)
        }
    }

    @Test func miniWindowRenders() throws {
        for (scene, name) in [(Demo.Scene.running, "running"), (.almostOut, "almost-out"), (.problem, "problem"), (.resting, "resting")] {
            model.show(scene)
            try save(MiniContent(model: model), as: "mini-\(name)", width: 280)
        }
        model.show(.running)
    }

    @Test func statusTextCoversEveryState() {
        for scene in Demo.Scene.allCases {
            model.show(scene)
            #expect(!model.headline.isEmpty)
            #expect(!model.detail.isEmpty)
        }
        model.show(.problem)
        #expect(model.status == .problem)
        #expect(model.headline == "Claude Code is signed out.")
        model.show(.running)
        #expect(model.headline.hasPrefix("Fresh window at"))
    }

    /// The main window around a screen: the sidebar, then the screen with its usual padding.
    private func window(_ screen: some View) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Sidebar(model: model)
            Divider()
            screen.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// Renders `view` in light and dark, and saves both if a snapshot folder is set.
    private func save(_ view: some View, as name: String, width: CGFloat = 420) throws {
        for scheme in [ColorScheme.light, .dark] {
            let framed = view
                .frame(width: width)
                .padding(width == 420 ? 16 : 0)
                .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.96))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: framed)
            renderer.scale = 2
            let image = try #require(renderer.nsImage)
            #expect(image.size.width > 0 && image.size.height > 0)

            guard let folder = ProcessInfo.processInfo.environment["TULOY_SNAPSHOTS"] else { continue }
            let png = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: folder).appending(path: "\(name)-\(scheme).png"))
        }
    }
}

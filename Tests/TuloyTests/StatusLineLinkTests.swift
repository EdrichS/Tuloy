import Foundation
import Testing
@testable import Tuloy

/// Connecting live usage edits Claude Code's settings file, so these tests are strict:
/// everything Tuloy didn't mean to change must come out exactly as it went in.
@Suite struct StatusLineLinkTests {

    /// A pretend home folder in a temporary directory: `.claude/settings.json` and `.tuloy/`.
    private struct Home {
        let root = FileManager.default.temporaryDirectory.appending(path: "tuloy-tests-\(UUID().uuidString)")
        var settings: URL { root.appending(path: ".claude/settings.json") }
        var folder: URL { root.appending(path: ".tuloy") }
        var link: StatusLineLink { StatusLineLink(settings: settings, folder: folder) }

        init(settings text: String?, claudeFolder: Bool = true) throws {
            if claudeFolder {
                try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            if let text { try text.write(to: settings, atomically: true, encoding: .utf8) }
        }

        var text: String { (try? String(contentsOf: settings, encoding: .utf8)) ?? "" }
        var statusLine: NSDictionary? { JSONText(text).object?["statusLine"] as? NSDictionary }
        func read(_ name: String) -> String? { try? String(contentsOf: folder.appending(path: name), encoding: .utf8) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private let plain = """
    {
      "model": "opus",
      "permissions": {"allow": ["Bash(ls)"]}
    }

    """

    private let withStatusLine = """
    {
      "model": "opus",
      "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2},
      "permissions": {"allow": ["Bash(ls)"]}
    }

    """

    // MARK: - Connecting

    @Test func addsAStatusLineAndLeavesTheRestAlone() throws {
        let home = try Home(settings: plain)
        defer { home.remove() }
        #expect(!home.link.isConnected)

        try home.link.connect()

        #expect(home.link.isConnected)
        #expect(home.text == """
        {
          "model": "opus",
          "permissions": {"allow": ["Bash(ls)"]},
          "statusLine": {
            "type": "command",
            "command": "\(home.link.command)"
          }
        }

        """)
        #expect(home.read("settings-backup.json") == plain)
        #expect(home.read("statusline-original.sh") == nil)
        #expect(FileManager.default.isExecutableFile(atPath: home.folder.appending(path: "statusline.sh").path(percentEncoded: false)))
    }

    @Test func keepsTheStatusLineYouHad() throws {
        let home = try Home(settings: withStatusLine)
        defer { home.remove() }

        try home.link.connect()

        #expect(home.statusLine == ["type": "command", "command": home.link.command, "padding": 2])
        #expect(home.read("statusline-original.sh") == "~/.claude/statusline.sh\n")
        // Only the status line changed: the lines around it are untouched.
        #expect(home.text.hasPrefix("{\n  \"model\": \"opus\",\n  \"statusLine\": {"))
        #expect(home.text.hasSuffix("},\n  \"permissions\": {\"allow\": [\"Bash(ls)\"]}\n}\n"))
    }

    @Test func connectingTwiceChangesNothingMore() throws {
        let home = try Home(settings: withStatusLine)
        defer { home.remove() }

        try home.link.connect()
        let once = home.text
        try home.link.connect()

        #expect(home.text == once)
        #expect(home.read("statusline-original.sh") == "~/.claude/statusline.sh\n")   // still yours, not Tuloy's
    }

    @Test func createsTheSettingsFileIfThereIsNone() throws {
        let home = try Home(settings: nil)
        defer { home.remove() }

        try home.link.connect()

        #expect(home.link.isConnected)
        #expect(home.statusLine == ["type": "command", "command": home.link.command])
    }

    @Test func followsALinkIntoYourDotfiles() throws {
        let home = try Home(settings: nil)
        defer { home.remove() }
        let dotfiles = home.root.appending(path: "dotfiles-settings.json")
        try plain.write(to: dotfiles, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: home.settings, withDestinationURL: dotfiles)

        try home.link.connect()

        let kind = try FileManager.default.attributesOfItem(atPath: home.settings.path(percentEncoded: false))[.type] as? FileAttributeType
        #expect(kind == .typeSymbolicLink)   // still a link
        #expect(try String(contentsOf: dotfiles, encoding: .utf8).contains("statusline.sh"))
    }

    @Test func writesTheHomeFolderAsATilde() {
        #expect(StatusLineLink().command == "~/.tuloy/statusline.sh")
    }

    // MARK: - Refusing

    @Test func leavesAFileItCannotReadAlone() throws {
        let broken = "{ \"model\": \"opus\", // my notes\n}"
        let home = try Home(settings: broken)
        defer { home.remove() }

        #expect(throws: StatusLineLink.LinkError.self) { try home.link.connect() }
        #expect(home.text == broken)
        #expect(!home.link.isConnected)
    }

    @Test func needsClaudeCodeToHaveRunOnce() throws {
        let home = try Home(settings: nil, claudeFolder: false)
        defer { home.remove() }

        #expect(throws: StatusLineLink.LinkError.self) { try home.link.connect() }
        #expect(!FileManager.default.fileExists(atPath: home.settings.path(percentEncoded: false)))
    }

    // MARK: - Disconnecting

    @Test func disconnectingPutsThePlainFileBackExactly() throws {
        let home = try Home(settings: plain)
        defer { home.remove() }

        try home.link.connect()
        try home.link.disconnect()

        #expect(home.text == plain)
        #expect(!home.link.isConnected)
        #expect(home.read("statusline.sh") == nil)
    }

    @Test func disconnectingRestoresTheStatusLineYouHad() throws {
        let home = try Home(settings: withStatusLine)
        defer { home.remove() }

        try home.link.connect()
        try home.link.disconnect()

        #expect(home.statusLine == ["type": "command", "command": "~/.claude/statusline.sh", "padding": 2])
        #expect(JSONText(home.text).object as NSDictionary? == JSONText(withStatusLine).object as NSDictionary?)
        #expect(home.read("statusline-original.sh") == nil)
    }

    @Test func disconnectingWhenNotConnectedTouchesNothing() throws {
        let home = try Home(settings: withStatusLine)
        defer { home.remove() }

        try home.link.disconnect()

        #expect(home.text == withStatusLine)
    }

    // MARK: - The script

    @Test func theScriptSavesTheDataAndRunsYourStatusLine() async throws {
        let home = try Home(settings: """
        {"statusLine": {"type": "command", "command": "tr a-z A-Z"}}
        """)
        defer { home.remove() }
        try home.link.connect()

        let input = #"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}"#
        let script = home.folder.appending(path: "statusline.sh").path(percentEncoded: false)
        let run = try await Shell.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf '%s' '\(input)' | '\(script)'"], timeout: 10)

        #expect(run.status == 0)
        #expect(run.output == input.uppercased())           // your status line still shows
        #expect(home.read("statusline.json") == input)      // and Tuloy got the data
        #expect(StatusLineFile.parse(Data(input.utf8), asOf: Date())?.window?.percent == 24)
    }
}

@Suite struct JSONTextTests {
    private let value: [String: Any] = ["type": "command", "command": "x"]

    private func setting(_ text: String) -> String {
        var json = JSONText(text)
        json.set("statusLine", to: value)
        return json.text
    }

    private func removing(_ text: String) -> String {
        var json = JSONText(text)
        json.remove("statusLine")
        return json.text
    }

    @Test func addsAtTheEndMatchingTheIndentation() {
        #expect(setting("{\n    \"a\": 1\n}") == "{\n    \"a\": 1,\n    \"statusLine\": {\n        \"type\": \"command\",\n        \"command\": \"x\"\n    }\n}")
        #expect(setting("{\n\t\"a\": 1\n}") == "{\n\t\"a\": 1,\n\t\"statusLine\": {\n\t\t\"type\": \"command\",\n\t\t\"command\": \"x\"\n\t}\n}")
    }

    @Test func staysOnOneLineInAOneLineFile() {
        #expect(setting(#"{"a":1}"#) == #"{"a":1,"statusLine": {"type": "command", "command": "x"}}"#)
    }

    @Test func fillsAnEmptyObject() {
        #expect(setting("{}") == "{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \"x\"\n  }\n}")
    }

    @Test func replacesOnlyTheTopLevelKey() {
        // The nested "statusLine" belongs to something else and must stay.
        let text = "{\n  \"other\": {\"statusLine\": 1},\n  \"statusLine\": \"old\",\n  \"z\": true\n}"
        #expect(setting(text) == "{\n  \"other\": {\"statusLine\": 1},\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \"x\"\n  },\n  \"z\": true\n}")
    }

    @Test func isNotFooledByBracesAndQuotesInsideStrings() {
        let text = #"{"note": "a } \" { b, \\", "list": [1, {"y": "]"}], "n": -1.5e3, "none": null}"#
        let result = JSONText(setting(text))
        #expect(result.text.hasPrefix(text.dropLast()))   // everything before the closing brace is unchanged
        #expect(result.object?["statusLine"] as? NSDictionary == value as NSDictionary)
        #expect(result.object?["note"] as? String == #"a } " { b, \"#)
    }

    @Test func removesAKeyWithItsComma() {
        #expect(removing("{\n  \"statusLine\": 1,\n  \"b\": 2\n}") == "{\n  \"b\": 2\n}")                  // first
        #expect(removing("{\n  \"a\": 1,\n  \"statusLine\": {\"x\": [1, 2]},\n  \"b\": 2\n}") == "{\n  \"a\": 1,\n  \"b\": 2\n}")   // middle
        #expect(removing("{\n  \"a\": 1,\n  \"statusLine\": 1\n}") == "{\n  \"a\": 1\n}")                  // last
        #expect(removing("{\n  \"statusLine\": 1\n}") == "{}")                                             // only
        #expect(removing("{\n  \"a\": 1\n}") == "{\n  \"a\": 1\n}")                                        // not there
    }

    @Test func leavesTextThatIsNotAnObjectAlone() {
        for text in ["", "[1, 2]", "{ \"a\": 1", "{ \"a\" 1 }", "{ // note\n}"] {
            #expect(setting(text) == text)
            #expect(removing(text) == text)
        }
    }
}

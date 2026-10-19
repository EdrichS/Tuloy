import Foundation

/// Connects Claude Code's status line to Tuloy with one click, so usage stays live while you work.
///
/// Connecting points the `statusLine` setting in ~/.claude/settings.json at a small script in
/// ~/.tuloy. The script saves the data Claude Code sends it, then runs the status line you
/// already had, so yours keeps working. Disconnecting puts everything back the way it was.
struct StatusLineLink {
    /// Claude Code's settings file.
    var settings = Paths.claudeSettings
    /// Tuloy's folder.
    var folder = Paths.tuloy

    enum LinkError: LocalizedError {
        case claudeCodeNotSetUp
        case unreadable

        var errorDescription: String? {
            switch self {
            case .claudeCodeNotSetUp: return "Claude Code's settings folder isn't there yet. Run \"claude\" in Terminal once, then try again."
            case .unreadable: return "Tuloy couldn't safely change Claude Code's settings file, so it left it alone. The README shows how to connect by hand."
            }
        }
    }

    /// True when Claude Code's status line runs Tuloy's script.
    var isConnected: Bool {
        statusLine(in: try? readSettings())?["command"] as? String == command
    }

    func connect() throws {
        var json = try readSettings()
        let current = statusLine(in: json) ?? [:]
        let existing = (current["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if existing != command {
            // Remember your own status line, so the script can keep running it and Disconnect can restore it.
            if existing.isEmpty {
                try? FileManager.default.removeItem(at: original)
            } else {
                try (existing + "\n").write(to: original, atomically: true, encoding: .utf8)
            }
        }
        try scriptText.write(to: scriptFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path(percentEncoded: false))

        var fields = current
        fields["type"] = "command"
        fields["command"] = command
        json.set("statusLine", to: fields)
        guard statusLine(in: json)?["command"] as? String == command else { throw LinkError.unreadable }
        try write(json)
    }

    func disconnect() throws {
        var json = try readSettings()
        if var fields = statusLine(in: json), fields["command"] as? String == command {
            let yours = (try? String(contentsOf: original, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if yours.isEmpty {
                // You had no status line before, so there's none to go back to.
                json.remove("statusLine")
                guard json.object != nil, statusLine(in: json) == nil else { throw LinkError.unreadable }
            } else {
                fields["command"] = yours
                json.set("statusLine", to: fields)
                guard statusLine(in: json)?["command"] as? String == yours else { throw LinkError.unreadable }
            }
            try write(json)
        }
        for file in [scriptFile, original, data] {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Files

    private var scriptFile: URL { folder.appending(path: "statusline.sh") }
    private var original: URL { folder.appending(path: "statusline-original.sh") }
    private var backup: URL { folder.appending(path: "settings-backup.json") }
    private var data: URL { folder.appending(path: "statusline.json") }

    /// What goes in Claude Code's settings: the script's path, written with ~ when it's in your home folder.
    var command: String {
        let path = scriptFile.path(percentEncoded: false)
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/"), !path.contains(" ") { return "~" + path.dropFirst(home.count) }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The script Claude Code runs as its status line.
    private var scriptText: String {
        """
        #!/bin/sh
        # Installed by Tuloy (Connection > Live usage). To remove it, choose Disconnect there.
        #
        # Claude Code runs this as its status line. It saves the data Claude Code sends,
        # so Tuloy can show your usage, then runs the status line you had before, if any.
        dir=$(cd "$(dirname "$0")" && pwd)
        input=$(cat)
        printf '%s' "$input" > "$dir/statusline.json.tmp" && mv -f "$dir/statusline.json.tmp" "$dir/statusline.json"
        if [ -f "$dir/statusline-original.sh" ]; then
            printf '%s' "$input" | sh "$dir/statusline-original.sh"
        fi

        """
    }

    private func statusLine(in json: JSONText?) -> [String: Any]? {
        json?.object?["statusLine"] as? [String: Any]
    }

    /// The settings file itself, even when ~/.claude/settings.json is a link into your dotfiles.
    private var realSettings: URL { settings.resolvingSymlinksInPath() }

    private func readSettings() throws -> JSONText {
        let path = realSettings.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            // No settings file yet is fine, as long as Claude Code has been run once.
            let claudeFolder = settings.deletingLastPathComponent().path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: claudeFolder) else { throw LinkError.claudeCodeNotSetUp }
            return JSONText("{}\n")
        }
        guard let text = try? String(contentsOf: realSettings, encoding: .utf8) else { throw LinkError.unreadable }
        let json = JSONText(text)
        guard json.object != nil else { throw LinkError.unreadable }
        return json
    }

    /// How long the copy of your settings is kept: long enough to notice anything amiss and put it back.
    static let backupKept: TimeInterval = 7 * 24 * 60 * 60

    /// Deletes the copy of your settings once it's over a week old.
    func forgetOldBackup(now: Date = Date()) {
        let path = backup.path(percentEncoded: false)
        guard let made = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
              now.timeIntervalSince(made) > StatusLineLink.backupKept
        else { return }
        try? FileManager.default.removeItem(at: backup)
    }

    /// Saves the settings file, keeping a copy of the old one and its permissions.
    /// The copy is readable only by you, and goes after a week (`forgetOldBackup`).
    private func write(_ json: JSONText) throws {
        guard json.object != nil else { throw LinkError.unreadable }
        let path = realSettings.path(percentEncoded: false)
        let permissions = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions]

        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(at: backup)
            // Made empty and private first, so the copy is never readable by anyone else, even for a moment.
            guard FileManager.default.createFile(atPath: backup.path(percentEncoded: false), contents: nil,
                                                 attributes: [.posixPermissions: 0o600])
            else { throw LinkError.unreadable }
            try Data(contentsOf: realSettings).write(to: backup)
        }
        try json.text.write(to: realSettings, atomically: true, encoding: .utf8)
        if let permissions {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        }
    }
}

/// A JSON file as text, for changing one top-level key while leaving every other
/// character (your order, your spacing) exactly as it was.
struct JSONText {
    private(set) var text: String

    init(_ text: String) {
        self.text = text
    }

    /// The file as a dictionary, or nil if it isn't a JSON object.
    var object: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// Sets a top-level key to a flat object, replacing its old value or adding it at the end.
    mutating func set(_ key: String, to fields: [String: Any]) {
        guard let layout = layout() else { return }
        let bytes = Array(text.utf8)
        // The space before the first key shows how the file is indented.
        let lead = layout.members.first.map { String(decoding: bytes[(layout.open + 1)..<$0.start], as: UTF8.self) } ?? "\n  "
        let indent = lead.lastIndex(of: "\n").map { String(lead[lead.index(after: $0)...]) }
        let value = JSONText.render(fields, indent: indent)

        if let member = layout.members.first(where: { $0.key == key }) {
            replace(member.valueStart..<member.end, with: value)
        } else if let last = layout.members.last {
            replace(last.end..<last.end, with: ",\(lead)\"\(key)\": \(value)")
        } else {
            replace((layout.open + 1)..<layout.close, with: "\(lead)\"\(key)\": \(value)\n")
        }
    }

    /// Removes a top-level key, along with its comma.
    mutating func remove(_ key: String) {
        guard let layout = layout(), let index = layout.members.firstIndex(where: { $0.key == key }) else { return }
        let member = layout.members[index]

        if index + 1 < layout.members.count {
            // Not the last key: take it and the comma after it, up to the next key.
            replace(member.start..<layout.members[index + 1].start, with: "")
        } else if index > 0 {
            // The last key: take the comma before it instead.
            replace(layout.members[index - 1].end..<member.end, with: "")
        } else {
            replace((layout.open + 1)..<layout.close, with: "")
        }
    }

    // MARK: - Finding the top-level keys

    private struct Member {
        var key: String
        var start: Int        // the key's opening quote
        var valueStart: Int
        var end: Int          // just past the value
    }

    private struct Layout {
        var open: Int         // the opening {
        var close: Int        // the closing }
        var members: [Member]
    }

    /// Walks the outermost object and notes where each key and value sits.
    private func layout() -> Layout? {
        let bytes = Array(text.utf8)
        var i = JSONText.skipSpace(bytes, from: 0)
        guard i < bytes.count, bytes[i] == UInt8(ascii: "{") else { return nil }
        let open = i
        i += 1

        var members: [Member] = []
        while true {
            i = JSONText.skipSpace(bytes, from: i)
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: "}") { return Layout(open: open, close: i, members: members) }

            guard let keyEnd = JSONText.endOfString(bytes, from: i) else { return nil }
            let key = String(decoding: bytes[(i + 1)..<(keyEnd - 1)], as: UTF8.self)
            let colon = JSONText.skipSpace(bytes, from: keyEnd)
            guard colon < bytes.count, bytes[colon] == UInt8(ascii: ":") else { return nil }
            let valueStart = JSONText.skipSpace(bytes, from: colon + 1)
            guard let end = JSONText.endOfValue(bytes, from: valueStart) else { return nil }
            members.append(Member(key: key, start: i, valueStart: valueStart, end: end))

            i = JSONText.skipSpace(bytes, from: end)
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") {
                i += 1
            } else if bytes[i] != UInt8(ascii: "}") {
                return nil
            }
        }
    }

    private static let space = Set(" \t\r\n".utf8)

    private static func skipSpace(_ bytes: [UInt8], from start: Int) -> Int {
        var i = start
        while i < bytes.count, space.contains(bytes[i]) { i += 1 }
        return i
    }

    /// The position just past the string that opens at `start`.
    private static func endOfString(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count, bytes[start] == UInt8(ascii: "\"") else { return nil }
        var i = start + 1
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "\\") {
                i += 2   // skip the escaped character
            } else if bytes[i] == UInt8(ascii: "\"") {
                return i + 1
            } else {
                i += 1
            }
        }
        return nil
    }

    /// The position just past the value that starts at `start`: a string, an object, an array, or a plain word.
    private static func endOfValue(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            return endOfString(bytes, from: start)

        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var i = start
            while i < bytes.count {
                switch bytes[i] {
                case UInt8(ascii: "\""):
                    guard let end = endOfString(bytes, from: i) else { return nil }
                    i = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default:
                    break
                }
                i += 1
            }
            return nil

        default:
            let stops = space.union(",}]".utf8)
            var i = start
            while i < bytes.count, !stops.contains(bytes[i]) { i += 1 }
            return i > start ? i : nil
        }
    }

    // MARK: - Writing

    private mutating func replace(_ range: Range<Int>, with new: String) {
        var bytes = Array(text.utf8)
        bytes.replaceSubrange(range, with: Array(new.utf8))
        text = String(decoding: bytes, as: UTF8.self)
    }

    /// A flat object as text: "type" and "command" first, then the rest by name.
    private static func render(_ fields: [String: Any], indent: String?) -> String {
        let first = ["type", "command"]
        let keys = first.filter { fields[$0] != nil } + fields.keys.filter { !first.contains($0) }.sorted()
        let pairs = keys.map { "\(fragment($0)): \(fragment(fields[$0] ?? NSNull()))" }

        guard let indent else { return "{" + pairs.joined(separator: ", ") + "}" }
        return "{\n" + pairs.map { indent + indent + $0 }.joined(separator: ",\n") + "\n" + indent + "}"
    }

    private static func fragment(_ value: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

import Foundation
import Yams

/// Changes to config.yaml made on its text, so the user's comments and layout survive:
/// a YAML round trip would drop every comment.
enum ConfigEditor {
    /// Adds a section for each of `entries` whose module the config doesn't have yet,
    /// in place of a commented-out `# id:` line among the `modules:` children when there
    /// is one, otherwise after the last module that's on (and the comments under it). A
    /// config without `modules:` gets one at the end. When the config doesn't parse, or
    /// wouldn't afterwards, the text comes back unchanged with nothing enabled.
    static func enablingModules(
        _ entries: [DefaultConfig.Entry],
        in yaml: String
    ) -> (yaml: String, enabled: [String]) {
        guard let before = Outline(yaml) else { return (yaml, []) }
        var missing: [DefaultConfig.Entry] = []
        for entry in entries where !before.modules.contains(entry.moduleID)
            && !missing.contains(where: { $0.moduleID == entry.moduleID })
        {
            missing.append(entry)
        }
        guard !missing.isEmpty else { return (yaml, []) }

        var lines = yaml.components(separatedBy: "\n")
        for entry in missing {
            guard insert(entry, into: &lines, hasModulesKey: before.hasModulesKey) else { return (yaml, []) }
        }
        let edited = lines.joined(separator: "\n")
        let enabled = missing.map(\.moduleID)
        guard let after = Outline(edited),
              after.modules == before.modules.union(enabled),
              after.topLevelKeys == before.topLevelKeys
        else {
            Log.config.error("Couldn't add modules to the config without breaking it; left it as it was")
            return (yaml, [])
        }
        return (edited, enabled)
    }

    /// What the edit has to keep intact: the top-level keys, and the enabled modules.
    private struct Outline {
        /// Always includes `modules`: one that's missing gets added.
        var topLevelKeys: Set<String> = ["modules"]
        var modules: Set<String> = []
        var hasModulesKey = false

        /// nil when the text isn't YAML, or `modules:` holds something other than a mapping.
        init?(_ yaml: String) {
            let root: Node?
            do {
                root = try Yams.compose(yaml: yaml)
            } catch {
                return nil
            }
            // An empty file has no root.
            guard let root else { return }
            guard let mapping = root.mapping else { return nil }
            let keys = Set(mapping.keys.compactMap(\.string))
            topLevelKeys.formUnion(keys)
            hasModulesKey = keys.contains("modules")
            if let node = mapping[Node("modules")], node.null == nil {
                guard let modulesMapping = node.mapping else { return nil }
                modules = Set(modulesMapping.keys.compactMap(\.string))
            }
        }
    }

    /// Puts `entry`'s section into the `modules:` block, or starts the block. False when
    /// `modules:` exists but not as a block of its own lines (`modules: {}`).
    private static func insert(_ entry: DefaultConfig.Entry, into lines: inout [String], hasModulesKey: Bool) -> Bool {
        guard let start = lines.firstIndex(where: isModulesKey) else {
            guard !hasModulesKey else { return false }
            let hasContent = lines.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let block = (hasContent ? [""] : []) + ["modules:"] + DefaultConfig.sectionLines(for: entry)
            // Before the empty string a trailing newline leaves at the end.
            lines.insert(contentsOf: block, at: lines.last?.isEmpty == true ? lines.count - 1 : lines.count)
            return true
        }
        let end = lines[(start + 1)...].firstIndex(where: isTopLevelContent) ?? lines.count
        let children = (start + 1) ..< end
        let firstChild = children.first { childIndent(of: lines[$0]) != nil }
        let indent = firstChild.flatMap { childIndent(of: lines[$0]) } ?? "  "
        let section = DefaultConfig.sectionLines(for: entry, indent: indent)
        if let commented = children.first(where: { isCommentedOut(entry.moduleID, lines[$0], indent: indent) }) {
            lines.replaceSubrange(commented ... commented, with: section)
        } else {
            var last = children.last { isContent(lines[$0]) } ?? start
            // Comments indented under that module (settings commented out) stay with it.
            while last + 1 < end, isComment(lines[last + 1], deeperThan: indent) {
                last += 1
            }
            lines.insert(contentsOf: section, at: last + 1)
        }
        return true
    }

    private static func isComment(_ line: String, deeperThan indent: String) -> Bool {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        return leading.count > indent.count && line.dropFirst(leading.count).hasPrefix("#")
    }

    /// `modules:` at the top level, holding nothing on its own line.
    private static func isModulesKey(_ line: String) -> Bool {
        line.range(of: #"^modules:[ \t]*(#.*)?\r?$"#, options: .regularExpression) != nil
    }

    private static func isTopLevelContent(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return !first.isWhitespace && first != "#"
    }

    private static func isContent(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("#")
    }

    /// The leading whitespace of a key line under `modules:`.
    private static func childIndent(of line: String) -> String? {
        guard isContent(line) else { return nil }
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        return indent.isEmpty ? nil : String(indent)
    }

    /// `  # spotify:` with an optional trailing comment, at the children's own indent:
    /// a module someone commented out. Deeper commented keys (a theme's `# ghostty:`
    /// override, say) don't count.
    private static func isCommentedOut(_ moduleID: String, _ line: String, indent: String) -> Bool {
        guard line.hasPrefix(indent + "#") else { return false }
        var rest = line.dropFirst(indent.count + 1)
        if rest.first == " " {
            rest = rest.dropFirst()
        }
        guard rest.hasPrefix(moduleID + ":") else { return false }
        let after = rest.dropFirst(moduleID.count + 1)
        return after.first.map { $0.isWhitespace } ?? true
    }
}

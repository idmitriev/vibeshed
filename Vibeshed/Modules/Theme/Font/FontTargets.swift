import Foundation

struct FontApplyRequest: Sendable {
    let font: ResolvedFont
    let config: ThemeConfig
    /// True while live-previewing: targets skip slow or irreversible work.
    let isPreview: Bool
}

/// An app `theme/switchFont` sets the font of. Shares `ThemeTargetID`s with the theme
/// targets: `targets:` in config limits both.
protocol FontTarget: Sendable {
    var id: ThemeTargetID { get }
    var displayName: String { get }

    /// Cheap and reversible, so it's safe to run on every highlight change. Such targets
    /// must implement `snapshot`.
    var supportsPreview: Bool { get }

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome

    /// Captures the state `apply` is about to change, for reverting a cancelled preview.
    func snapshot(config: ThemeConfig) async -> ThemeRestore?

    /// The family the app is set to now, if it's cheap to tell.
    func currentFamily(config: ThemeConfig) -> String?
}

extension FontTarget {
    var supportsPreview: Bool { false }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? { nil }

    func currentFamily(config _: ThemeConfig) -> String? { nil }
}

// MARK: - Ghostty

/// Ghostty: the first `font-family` line of its config names the terminal family (later
/// ones are fallbacks and stay), then open terminals reload, as for the theme.
struct GhosttyFontTarget: FontTarget {
    let id = ThemeTargetID.ghostty
    let displayName = "Ghostty"
    var supportsPreview: Bool { true }

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome {
        guard GhosttyApp.isInstalled || ThemeFiles.exists(GhosttyTarget.configDirectory) else {
            return .skipped("not installed")
        }
        do {
            try Self.selectFamily(
                request.font.terminalFamily, paths: GhosttyTarget.configPaths, newFile: GhosttyTarget.newConfigPath
            )
        } catch {
            return .failed(error.localizedDescription)
        }
        let reload = GhosttyApp.reloadConfig()
        guard !request.isPreview, reload.outdated > 0 else { return .applied() }
        return .applied(note: "Ghostty before 1.2 can't reload on its own: press ⌘⇧, in it")
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        let files = ThemeFiles.snapshot(GhosttyTarget.configPaths)
        return {
            await files()
            GhosttyApp.reloadConfig()
        }
    }

    func currentFamily(config _: ThemeConfig) -> String? {
        // The last file Ghostty loads wins.
        GhosttyTarget.configPaths.reversed().lazy.compactMap { ThemeFiles.read($0).flatMap(Self.family(in:)) }.first
    }

    /// Points the first `font-family` of every config file that has one at `family`; with
    /// none anywhere, appends one to the file Ghostty loads last (or creates `newFile`).
    static func selectFamily(_ family: String, paths: [String], newFile: String) throws {
        let existing = paths.filter(ThemeFiles.exists)
        var selected = false
        for path in existing {
            guard let text = ThemeFiles.read(path) else { throw ThemeTargetError.unreadable(path) }
            guard let updated = replacingFamily(family, in: text) else { continue }
            try ThemeFiles.write(updated, to: path)
            selected = true
        }
        guard !selected else { return }
        let path = existing.last ?? newFile
        let config = ThemeFiles.read(path) ?? ""
        let separator = config.isEmpty || config.hasSuffix("\n") ? "" : "\n"
        try ThemeFiles.write(config + separator + "font-family = \(family)\n", to: path)
    }

    /// `config` with its first `font-family` naming `family`, or nil when it names none.
    static func replacingFamily(_ family: String, in config: String) -> String? {
        var lines = config.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { familyValue(of: $0) != nil }) else { return nil }
        lines[index] = "font-family = \(family)"
        return lines.joined(separator: "\n")
    }

    /// The family the first `font-family` of `config` names.
    static func family(in config: String) -> String? {
        config.components(separatedBy: "\n").lazy.compactMap(familyValue(of:)).first
    }

    /// The family a `font-family = …` line names, unquoted. An empty value resets the
    /// list rather than naming a font, so it doesn't count.
    private static func familyValue(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "="),
              trimmed[..<equals].trimmingCharacters(in: .whitespaces) == "font-family"
        else { return nil }
        let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return value.isEmpty ? nil : value
    }
}

// MARK: - VS Code

/// VS Code and its forks: `editor.fontFamily` leads with the editor family, and a
/// `terminal.integrated.fontFamily` of its own with the terminal family; fallback
/// families after the first are kept. Settings apply live.
struct VSCodeFontTarget: FontTarget {
    let id = ThemeTargetID.vscode
    let displayName = "VS Code"
    var supportsPreview: Bool { true }

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome {
        let editors = VSCodeTarget.editors(request.config)
        guard !editors.isEmpty else { return .skipped("not installed") }
        var failures: [String] = []
        for editor in editors {
            do {
                var settings = JSONCDocument(text: ThemeFiles.read(editor.settingsPath))
                try Self.apply(request.font, to: &settings)
                try ThemeFiles.write(settings.text, to: editor.settingsPath)
            } catch {
                failures.append("\(editor.name): \(error.localizedDescription)")
            }
        }
        return failures.isEmpty ? .applied() : .failed(failures.joined(separator: "; "))
    }

    func snapshot(config: ThemeConfig) async -> ThemeRestore? {
        let paths = VSCodeTarget.editors(config).map(\.settingsPath)
        return paths.isEmpty ? nil : ThemeFiles.snapshot(paths)
    }

    func currentFamily(config: ThemeConfig) -> String? {
        VSCodeTarget.editors(config).lazy.compactMap { editor in
            (JSONCDocument(text: ThemeFiles.read(editor.settingsPath)).value(forKey: "editor.fontFamily") as? String)?
                .split(separator: ",").first
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) }
        }.first
    }

    static func apply(_ font: ResolvedFont, to settings: inout JSONCDocument) throws {
        let editorKey = "editor.fontFamily"
        let editorList = fontList(font.editorFamily, replacingFirstOf: settings.value(forKey: editorKey) as? String)
        try settings.setValue(editorList, forKey: editorKey)
        let terminalKey = "terminal.integrated.fontFamily"
        if let terminal = settings.value(forKey: terminalKey) as? String,
           !terminal.trimmingCharacters(in: .whitespaces).isEmpty
        {
            try settings.setValue(fontList(font.terminalFamily, replacingFirstOf: terminal), forKey: terminalKey)
        }
    }

    /// A CSS font list: `family`, then the fallbacks `list` had after its first family.
    static func fontList(_ family: String, replacingFirstOf list: String?) -> String {
        let fallbacks = (list ?? "").split(separator: ",").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) != family }
        return ([cssName(family)] + fallbacks).joined(separator: ", ")
    }

    /// Quoted unless it's a plain identifier (no spaces, not starting with a digit).
    static func cssName(_ family: String) -> String {
        let isIdentifier = family.first?.isLetter == true
            && family.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        return isIdentifier ? family : "'\(family)'"
    }
}

// MARK: - Zed

/// Zed: `buffer_font_family` gets the editor family — and `ui_font_family` too while it's
/// the same font as the buffer's (a monospaced UI) — and a `terminal.font_family` of its
/// own the terminal family. Settings apply live.
struct ZedFontTarget: FontTarget {
    let id = ThemeTargetID.zed
    let displayName = "Zed"
    var supportsPreview: Bool { true }

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome {
        guard ThemeFiles.exists(ZedTarget.configDir) || ThemeApps.isInstalled(ZedTarget.bundleID) else {
            return .skipped("not installed")
        }
        do {
            var settings = JSONCDocument(text: ThemeFiles.read(ZedTarget.settingsPath))
            try Self.apply(request.font, to: &settings)
            try ThemeFiles.write(settings.text, to: ZedTarget.settingsPath)
            return .applied()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        ThemeFiles.snapshot([ZedTarget.settingsPath])
    }

    func currentFamily(config _: ThemeConfig) -> String? {
        JSONCDocument(text: ThemeFiles.read(ZedTarget.settingsPath)).value(forKey: "buffer_font_family") as? String
    }

    static func apply(_ font: ResolvedFont, to settings: inout JSONCDocument) throws {
        let previous = settings.value(forKey: "buffer_font_family") as? String
        try settings.setValue(font.editorFamily, forKey: "buffer_font_family")
        if let previous, settings.value(forKey: "ui_font_family") as? String == previous {
            try settings.setValue(font.editorFamily, forKey: "ui_font_family")
        }
        if settings.value(at: ["terminal", "font_family"]) is String {
            try settings.setValue(font.terminalFamily, at: ["terminal", "font_family"])
        }
    }
}

// MARK: - JetBrains

/// JetBrains IDEs (newest config folder per product): the editor font, the terminal and
/// console fonts where they're set apart from it, and the fonts the color scheme in use
/// overrides them with. IDEs read these at startup, so it's excluded from live preview.
struct JetBrainsFontTarget: FontTarget {
    let id = ThemeTargetID.jetbrains
    let displayName = "JetBrains"

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome {
        let folders = JetBrainsTarget.configFolders(enabled: request.config.jetbrainsIDEs)
        guard !folders.isEmpty else { return .skipped("not installed") }
        var failures: [String] = []
        for folder in folders {
            do {
                try Self.apply(request.font, to: folder)
            } catch {
                failures.append("\(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else { return .failed(failures.joined(separator: "; ")) }
        return .applied(note: "restart JetBrains IDEs to load it")
    }

    private static func apply(_ font: ResolvedFont, to folder: URL) throws {
        let options = folder.appendingPathComponent("options")
        try JetBrainsXML.setOption(
            "FONT_FAMILY", font.editorFamily, component: "DefaultFont",
            at: options.appendingPathComponent("editor-font.xml").path, onlyIfSet: false
        )
        for (file, component) in [("terminal-font.xml", "TerminalFontOptions"), ("console-font.xml", "ConsoleFont")] {
            try JetBrainsXML.setOption(
                "FONT_FAMILY", font.terminalFamily, component: component,
                at: options.appendingPathComponent(file).path, onlyIfSet: true
            )
        }

        // A scheme can carry fonts of its own ("Use color scheme font instead of the default").
        guard let scheme = JetBrainsXML.globalScheme(at: options.appendingPathComponent("colors.scheme.xml").path)
        else { return }
        let schemePath = [scheme, "_@user_\(scheme)"]
            .map { folder.appendingPathComponent("colors/\($0).icls").path }
            .first(where: ThemeFiles.exists)
        guard let schemePath, var text = ThemeFiles.read(schemePath) else { return }
        for (option, family) in [("EDITOR_FONT_NAME", font.editorFamily), ("CONSOLE_FONT_NAME", font.terminalFamily)] {
            text = replacingOption(option, with: family, in: text) ?? text
        }
        try ThemeFiles.write(text, to: schemePath)
    }

    /// `scheme` (an `.icls`) with the value of `<option name="<name>" value="…"/>`
    /// replaced, or nil when it has no such option.
    static func replacingOption(_ name: String, with value: String, in scheme: String) -> String? {
        let pattern = #"(<option name="\#(name)" value=")[^"]*(")"#
        guard let range = scheme.range(of: pattern, options: .regularExpression) else { return nil }
        let escaped = value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return scheme.replacingCharacters(in: range, with: "<option name=\"\(name)\" value=\"\(escaped)\"")
    }
}

import Foundation

/// VS Code and its forks. Like Omarchy's `omarchy-theme-set-vscode`: the palette becomes a
/// local theme extension ("Vibeshed", contributed with `_watch: true` so VS Code reloads
/// the file on change), registered in the editor's `extensions.json`, and selected via
/// `workbench.colorTheme` in `settings.json` — which VS Code also applies live.
/// `apps: { vscode: "<theme name>" }` selects an installed theme instead.
struct VSCodeTarget: ThemeTarget {
    let id = ThemeTargetID.vscode
    let displayName = "VS Code"
    var supportsPreview: Bool { true }

    static let themeLabel = "Vibeshed"
    private static let extensionName = "vibeshed-theme"
    private static let extensionID = "vibeshed.\(extensionName)"

    struct Editor: Sendable {
        let name: String
        /// Folder under `~/Library/Application Support`.
        let supportDir: String
        /// Extensions folder under `~`, when known.
        let extensionsDir: String?

        var settingsPath: String {
            ThemeFiles.home.appendingPathComponent("Library/Application Support/\(supportDir)/User/settings.json").path
        }

        var extensionsRoot: String? {
            extensionsDir.map { ThemeFiles.home.appendingPathComponent("\($0)/extensions").path }
        }

        var isInstalled: Bool {
            ThemeFiles.exists((settingsPath as NSString).deletingLastPathComponent)
        }
    }

    private static let knownEditors: [Editor] = [
        Editor(name: "VS Code", supportDir: "Code", extensionsDir: ".vscode"),
        Editor(name: "VS Code Insiders", supportDir: "Code - Insiders", extensionsDir: ".vscode-insiders"),
        Editor(name: "Cursor", supportDir: "Cursor", extensionsDir: ".cursor"),
        Editor(name: "Windsurf", supportDir: "Windsurf", extensionsDir: ".windsurf"),
        Editor(name: "VSCodium", supportDir: "VSCodium", extensionsDir: ".vscode-oss"),
    ]

    static func editors(_ config: ThemeConfig) -> [Editor] {
        guard let configured = config.vscodeVariants else { return knownEditors.filter(\.isInstalled) }
        return configured.sorted { $0.key < $1.key }.map { name, dir in
            let known = knownEditors.first { $0.supportDir == dir }
            return Editor(name: name, supportDir: dir, extensionsDir: known?.extensionsDir)
        }.filter(\.isInstalled)
    }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let editors = Self.editors(request.config)
        guard !editors.isEmpty else { return .skipped("not installed") }

        var failures: [String] = []
        for editor in editors {
            do {
                try Self.apply(request, to: editor)
            } catch {
                failures.append("\(editor.name): \(error.localizedDescription)")
            }
        }
        return failures.isEmpty ? .applied() : .failed(failures.joined(separator: "; "))
    }

    func snapshot(config: ThemeConfig) async -> ThemeRestore? {
        let paths = Self.editors(config).flatMap { editor -> [String] in
            var paths = [editor.settingsPath]
            if let root = editor.extensionsRoot {
                paths += [
                    "\(root)/extensions.json",
                    "\(root)/\(Self.extensionName)/package.json",
                    "\(root)/\(Self.extensionName)/themes/vibeshed-color-theme.json",
                ]
            }
            return paths
        }
        return paths.isEmpty ? nil : ThemeFiles.snapshot(paths)
    }

    private static func apply(_ request: ThemeApplyRequest, to editor: Editor) throws {
        let themeName: String
        if let override = request.override(.vscode) {
            themeName = override
        } else if let root = editor.extensionsRoot {
            try installExtension(request.palette, root: root)
            themeName = themeLabel
        } else {
            return
        }

        var settings = JSONCDocument(text: ThemeFiles.read(editor.settingsPath))
        try settings.setValue(themeName, forKey: "workbench.colorTheme")
        // With OS-synced themes on, VS Code ignores colorTheme in favor of these.
        if settings.value(forKey: "window.autoDetectColorScheme") as? Bool == true {
            let key = request.palette.mode == .dark
                ? "workbench.preferredDarkColorTheme" : "workbench.preferredLightColorTheme"
            try settings.setValue(themeName, forKey: key)
        }
        try ThemeFiles.write(settings.text, to: editor.settingsPath)
    }

    // MARK: - Extension

    private static func installExtension(_ palette: ThemePalette, root: String) throws {
        let theme = VSCodeThemeBuilder.theme(palette, name: themeLabel)
        let themeData = try JSONFormatting.pretty(theme)
        // VS Code caches color themes per extension version, so derive the version from
        // the content: same palette keeps the cache, a new one invalidates it.
        let version = "1.0.\(checksum(themeData))"
        let folder = "\(root)/\(extensionName)"

        try ThemeFiles.write(themeData + "\n", to: "\(folder)/themes/vibeshed-color-theme.json")
        let manifest: [String: Any] = [
            "name": extensionName,
            "displayName": "Vibeshed",
            "description": "Colors of the active Vibeshed theme",
            "publisher": "vibeshed",
            "version": version,
            "engines": ["vscode": "^1.70.0"],
            "categories": ["Themes"],
            "contributes": [
                "themes": [[
                    "label": themeLabel,
                    "uiTheme": palette.mode == .dark ? "vs-dark" : "vs",
                    "path": "./themes/vibeshed-color-theme.json",
                    "_watch": true,
                ]],
            ],
        ]
        try ThemeFiles.writeJSON(manifest, to: "\(folder)/package.json")
        try register(folder: folder, version: version, root: root)
    }

    /// Adds (or refreshes) the extension's entry in `extensions.json`, the list VS Code
    /// loads installed extensions from, and un-marks it as obsolete.
    private static func register(folder: String, version: String, root: String) throws {
        let listPath = "\(root)/extensions.json"
        var entries: [[String: Any]] = []
        if let text = ThemeFiles.read(listPath) {
            // Never rewrite a list we couldn't read — that would uninstall everything else.
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
                throw ThemeTargetError.unreadable(listPath)
            }
            entries = parsed
        }
        entries.removeAll { ($0["identifier"] as? [String: Any])?["id"] as? String == extensionID }
        entries.append([
            "identifier": ["id": extensionID],
            "version": version,
            "location": [
                "$mid": 1, "fsPath": folder, "external": "file://\(folder)", "path": folder, "scheme": "file",
            ],
            "relativeLocation": extensionName,
        ])
        try ThemeFiles.writeJSON(entries, to: listPath)

        let obsoletePath = "\(root)/.obsolete"
        if var obsolete = ThemeFiles.read(obsoletePath)
            .flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) }) as? [String: Any],
            obsolete.keys.contains(where: { $0.hasPrefix(extensionID) })
        {
            obsolete = obsolete.filter { !$0.key.hasPrefix(extensionID) }
            try ThemeFiles.writeJSON(obsolete, to: obsoletePath)
        }
    }

    private static func checksum(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash
    }
}

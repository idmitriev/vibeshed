import Foundation

/// JetBrains IDEs (newest config folder per product). Writes the palette as a user
/// editor scheme (`colors/_@user_Vibeshed.icls`, keeping the current scheme's fonts),
/// makes it the global scheme, and — when "Sync with OS" is on — the preferred scheme
/// for the palette's mode, so the IDE follows the appearance switch. IDEs load schemes
/// at startup, so this takes effect on restart; it's excluded from live preview.
/// `apps: { jetbrains: "<scheme id>" }` selects an existing scheme instead.
struct JetBrainsTarget: ThemeTarget {
    let id = ThemeTargetID.jetbrains
    let displayName = "JetBrains"

    static let schemeID = "_@user_Vibeshed"

    private static var root: URL {
        ThemeFiles.home.appendingPathComponent("Library/Application Support/JetBrains")
    }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let folders = Self.configFolders(enabled: request.config.jetbrainsIDEs)
        guard !folders.isEmpty else { return .skipped("not installed") }

        var failures: [String] = []
        for folder in folders {
            do {
                try Self.apply(request, to: folder)
            } catch {
                failures.append("\(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else { return .failed(failures.joined(separator: "; ")) }
        return .applied(note: "restart JetBrains IDEs to load it")
    }

    /// The newest config folder of each known IDE, e.g. `IntelliJIdea2026.1`.
    static func configFolders(enabled: Set<String>?) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var newest: [String: String] = [:]
        for entry in entries {
            guard let info = JetBrainsIDEInfo.known.first(where: { entry.hasPrefix($0.dirPrefix) }),
                  entry.dropFirst(info.dirPrefix.count).first?.isNumber == true,
                  enabled?.contains(info.tag) ?? true
            else { continue }
            if let current = newest[info.dirPrefix],
               current.compare(entry, options: .numeric) != .orderedAscending
            {
                continue
            }
            newest[info.dirPrefix] = entry
        }
        return newest.values.sorted().map { root.appendingPathComponent($0) }
    }

    private static func apply(_ request: ThemeApplyRequest, to folder: URL) throws {
        let options = folder.appendingPathComponent("options")
        let schemesPath = options.appendingPathComponent("colors.scheme.xml").path
        let scheme: String
        if let override = request.override(.jetbrains) {
            scheme = override
        } else {
            let fonts = currentFontOptions(folder: folder, schemesPath: schemesPath)
            let icls = JetBrainsSchemeBuilder.scheme(request.palette, id: schemeID, fontOptions: fonts)
            try ThemeFiles.write(icls, to: folder.appendingPathComponent("colors/\(schemeID).icls").path)
            scheme = schemeID
        }

        try JetBrainsXML.setGlobalScheme(scheme, at: schemesPath)
        try JetBrainsXML.setPreferredScheme(
            scheme, dark: request.palette.mode == .dark, at: options.appendingPathComponent("laf.xml").path
        )
    }

    /// Font/spacing options of the scheme in use, so switching themes keeps the editor font.
    private static func currentFontOptions(folder: URL, schemesPath: String) -> [String] {
        let current = JetBrainsXML.globalScheme(at: schemesPath) ?? schemeID
        let candidates = [current, "_@user_\(current)"].map {
            folder.appendingPathComponent("colors/\($0).icls").path
        }
        guard let text = candidates.lazy.compactMap(ThemeFiles.read).first else { return [] }
        let fontKeys = ["FONT_SCALE", "LINE_SPACING", "EDITOR_FONT_SIZE", "EDITOR_FONT_NAME", "EDITOR_LIGATURES",
                        "CONSOLE_FONT_NAME", "CONSOLE_FONT_SIZE", "CONSOLE_LINE_SPACING"]
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in fontKeys.contains { line.hasPrefix("<option name=\"\($0)\"") } }
    }
}

// MARK: - Options XML

/// Targeted edits to JetBrains option files — only the element being changed; every
/// other setting in the file is preserved.
enum JetBrainsXML {
    static func globalScheme(at path: String) -> String? {
        guard let document = try? XMLDocument(contentsOf: URL(fileURLWithPath: path)),
              let element = try? document.nodes(forXPath: "//global_color_scheme").first as? XMLElement
        else { return nil }
        return element.attribute(forName: "name")?.stringValue
    }

    static func setGlobalScheme(_ scheme: String, at path: String) throws {
        let document = try load(path, fallback: "<application/>")
        let component = component(named: "EditorColorsManagerImpl", in: document)
        let global = child("global_color_scheme", of: component)
        setAttribute("name", scheme, on: global)
        try save(document, to: path)
    }

    /// Only with "Sync with OS" (`autodetect="true"`) — otherwise the IDE ignores these.
    static func setPreferredScheme(_ scheme: String, dark: Bool, at path: String) throws {
        guard let document = try? XMLDocument(contentsOf: URL(fileURLWithPath: path)),
              let laf = try? document.nodes(forXPath: "//component[@name='LafManager']").first as? XMLElement,
              laf.attribute(forName: "autodetect")?.stringValue == "true"
        else { return }
        let preferred = child(dark ? "preferred-dark-editor-scheme" : "preferred-light-editor-scheme", of: laf)
        setAttribute("editorSchemeId", scheme, on: preferred)
        try save(document, to: path)
    }

    private static func load(_ path: String, fallback: String) throws -> XMLDocument {
        guard ThemeFiles.exists(path) else { return try XMLDocument(xmlString: fallback) }
        // Never replace a file we couldn't parse.
        guard let document = try? XMLDocument(contentsOf: URL(fileURLWithPath: path)) else {
            throw ThemeTargetError.unreadable(path)
        }
        return document
    }

    private static func component(named name: String, in document: XMLDocument) -> XMLElement {
        if let existing = try? document.nodes(forXPath: "//component[@name='\(name)']").first as? XMLElement {
            return existing
        }
        let element = XMLElement(name: "component")
        element.setAttributesWith(["name": name])
        document.rootElement()?.addChild(element)
        return element
    }

    private static func child(_ name: String, of parent: XMLElement) -> XMLElement {
        if let existing = parent.elements(forName: name).first { return existing }
        let element = XMLElement(name: name)
        parent.addChild(element)
        return element
    }

    /// Sets one attribute, keeping the element's others.
    private static func setAttribute(_ name: String, _ value: String, on element: XMLElement) {
        var attributes: [String: String] = [:]
        for attribute in element.attributes ?? [] {
            if let key = attribute.name { attributes[key] = attribute.stringValue ?? "" }
        }
        attributes[name] = value
        element.setAttributesWith(attributes)
    }

    private static func save(_ document: XMLDocument, to path: String) throws {
        guard let root = document.rootElement() else { return }
        try ThemeFiles.write(root.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement]) + "\n", to: path)
    }
}

import ApplicationServices

/// Reads the picker's result list through Accessibility. Rows are
/// AXStaticText title/subtitle pairs inside the list's AXScrollArea; the
/// preview pane's texts sit outside it.
@MainActor
enum PickerResults {
    /// The first row's title — the row Return runs right after typing.
    static func topTitle() -> String? {
        topTexts(2).first
    }

    /// The first row's title and subtitle, to tell one list from another when titles
    /// repeat (Wallhaven's are resolutions).
    static func topRow() -> String? {
        let texts = topTexts(2)
        return texts.isEmpty ? nil : texts.joined(separator: " · ")
    }

    /// Every row's title, top to bottom. The list is flat: one group holding each row's
    /// icon (an image), then its title, subtitle and badges as texts. So a row's title
    /// is the first text after an image.
    static func rowTitles() -> [String] {
        guard let picker = Windows.picker() else { return [] }
        let app = AXUIElementCreateApplication(picker.pid)
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            guard let list = first(in: window, depth: 8, where: { role(of: $0) == kAXScrollAreaRole }),
                  let rows = first(in: list, depth: 6, where: { element in
                      children(of: element, attribute: kAXChildrenAttribute)
                          .filter { role(of: $0) == kAXImageRole }.count >= 2
                  })
            else { continue }
            var titles: [String] = []
            var afterIcon = false
            for element in children(of: rows, attribute: kAXChildrenAttribute) {
                if role(of: element) == kAXImageRole {
                    afterIcon = true
                } else if afterIcon, role(of: element) == kAXStaticTextRole, !value(of: element).isEmpty {
                    titles.append(value(of: element))
                    afterIcon = false
                }
            }
            if !titles.isEmpty { return titles }
        }
        return []
    }

    /// The texts outside the result list: the preview pane's (title first) and the
    /// search field's breadcrumbs. The preview follows the highlighted row once the
    /// list has been still for a moment.
    static func previewTexts() -> [String] {
        guard let picker = Windows.picker() else { return [] }
        let app = AXUIElementCreateApplication(picker.pid)
        var texts: [String] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 14, texts.count < 40 else { return }
            if role(of: element) == kAXScrollAreaRole { return }
            if role(of: element) == kAXStaticTextRole, !value(of: element).isEmpty { texts.append(value(of: element)) }
            for kid in children(of: element, attribute: kAXChildrenAttribute) { walk(kid, depth + 1) }
        }
        for window in children(of: app, attribute: kAXWindowsAttribute) { walk(window, 0) }
        return texts
    }

    /// The result list's Accessibility tree, one element per line (role, child count,
    /// value), for errors when the rows can't be found.
    static func treeSummary(maxLines: Int = 80) -> String {
        guard let picker = Windows.picker() else { return "no picker" }
        let app = AXUIElementCreateApplication(picker.pid)
        var lines: [String] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard lines.count < maxLines, depth < 14 else { return }
            let kids = children(of: element, attribute: kAXChildrenAttribute)
            let text = value(of: element)
            lines.append(String(repeating: "  ", count: depth) + "\(role(of: element)) [\(kids.count)]"
                + (text.isEmpty ? "" : " “\(text.prefix(40))”"))
            for kid in kids { walk(kid, depth + 1) }
        }
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            if let list = first(in: window, depth: 8, where: { role(of: $0) == kAXScrollAreaRole }) {
                walk(list, 0)
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The list's first `count` non-empty texts, in order.
    private static func topTexts(_ count: Int) -> [String] {
        guard let picker = Windows.picker() else { return [] }
        let app = AXUIElementCreateApplication(picker.pid)
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            guard let list = first(in: window, depth: 8, where: { role(of: $0) == kAXScrollAreaRole }) else {
                continue
            }
            var texts: [String] = []
            collectTexts(in: list, depth: 10, into: &texts, limit: count)
            if !texts.isEmpty { return texts }
        }
        return []
    }

    private static func collectTexts(in element: AXUIElement, depth: Int, into texts: inout [String], limit: Int) {
        guard depth > 0 else { return }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            guard texts.count < limit else { return }
            if role(of: child) == kAXStaticTextRole, !value(of: child).isEmpty {
                texts.append(value(of: child))
            }
            collectTexts(in: child, depth: depth - 1, into: &texts, limit: limit)
        }
    }

    private static func first(
        in element: AXUIElement,
        depth: Int,
        where matches: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard depth > 0 else { return nil }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            if matches(child) { return child }
            if let found = first(in: child, depth: depth - 1, where: matches) { return found }
        }
        return nil
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    private static func value(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return value as? String ?? ""
    }
}

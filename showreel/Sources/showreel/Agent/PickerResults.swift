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

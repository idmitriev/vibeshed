import ApplicationServices

/// Reads the picker's result list through Accessibility. Rows are
/// AXStaticText title/subtitle pairs inside the list's AXScrollArea; the
/// preview pane's texts sit outside it.
@MainActor
enum PickerResults {
    /// The first row's title — the row Return runs right after typing.
    static func topTitle() -> String? {
        guard let picker = Windows.picker() else { return nil }
        let app = AXUIElementCreateApplication(picker.pid)
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            guard let list = first(in: window, depth: 8, where: { role(of: $0) == kAXScrollAreaRole }) else {
                continue
            }
            let title = first(in: list, depth: 10) { role(of: $0) == kAXStaticTextRole && !value(of: $0).isEmpty }
            if let title { return value(of: title) }
        }
        return nil
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

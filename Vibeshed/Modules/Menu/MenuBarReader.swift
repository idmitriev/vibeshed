import AppKit
import ApplicationServices
import OSLog

private let log = Log.module("menu")

/// The app whose menu bar the menu actions read and press.
struct MenuTarget: Sendable, Equatable {
    let pid: pid_t
    let name: String
    let bundleID: String?
    let bundleURL: URL?

    /// The app that owns the menu bar. The picker panel doesn't activate Vibeshed,
    /// so while it's open this is still the app the user was working in.
    @MainActor
    static func current() -> MenuTarget? {
        let workspace = NSWorkspace.shared
        guard let app = workspace.menuBarOwningApplication ?? workspace.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }
        return MenuTarget(
            pid: app.processIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "App",
            bundleID: app.bundleIdentifier,
            bundleURL: app.bundleURL
        )
    }
}

enum MenuPressOutcome: Sendable, Equatable {
    case pressed
    case notFound
    case disabled
    case failed(AXError)
}

/// Reads and presses an app's menu bar items through the Accessibility API.
///
/// Every AX call is a synchronous round trip serviced on the target app's main
/// thread, so all work runs on a private serial queue — never the main actor or the
/// cooperative pool — with a short per-call timeout so a hung app can't stall it.
enum MenuBarReader {
    private static let queue = DispatchQueue(label: "com.ivandmitriev.Vibeshed.menu", qos: .userInitiated)
    /// Per AX call. A pressed item that opens a modal dialog holds up the reply too,
    /// so this also bounds how long a press waits for one.
    private static let messagingTimeout: Float = 0.5
    /// Whole-crawl budget, under ModuleRegistry's 2s per-module query timeout.
    private static let crawlBudget: TimeInterval = 1.0
    private static let maxEntries = 3000

    /// Every enabled leaf item in the menus of `pid`, top-level items first. Submenus
    /// holding more than `maxSubmenuItems` items are skipped.
    static func entries(pid: pid_t, maxSubmenuItems: Int) async -> [MenuItemEntry] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: crawl(pid: pid, maxSubmenuItems: maxSubmenuItems))
            }
        }
    }

    /// Presses the item at `path` in `pid`'s menu bar. Titles match exactly first,
    /// then loosely (see `MenuPath.normalized`).
    static func press(path: [String], pid: pid_t) async -> MenuPressOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: pressItem(at: path, pid: pid))
            }
        }
    }

    // MARK: - Crawl

    private static func crawl(pid: pid_t, maxSubmenuItems: Int) -> [MenuItemEntry] {
        let start = Date()
        let deadline = start.addingTimeInterval(crawlBudget)
        guard let menuBar = menuBar(of: pid) else { return [] }

        // Breadth-first, so a crawl cut short by the budget keeps the shallow
        // commands. Menu bar item 0 is the Apple menu: system-wide, not the app's.
        var pending: [(menu: AXUIElement, path: [String])] = children(of: menuBar).dropFirst().compactMap { item in
            guard let info = itemInfo(of: item), info.isEnabled, !info.title.isEmpty,
                  let submenu = info.submenu
            else {
                return nil
            }
            return (submenu, [info.title])
        }
        var entries: [MenuItemEntry] = []
        var seenKeys: Set<String> = []
        var next = 0
        while next < pending.count, entries.count < maxEntries, Date() < deadline {
            let (menu, path) = pending[next]
            next += 1
            let items = children(of: menu)
            if path.count > 1, items.count > maxSubmenuItems { continue }

            for item in items {
                // Separators and custom views are untitled; section headers are disabled.
                guard let info = itemInfo(of: item), info.isEnabled, !info.title.isEmpty else { continue }
                let itemPath = path + [info.title]
                if let submenu = info.submenu {
                    pending.append((submenu, itemPath))
                } else if seenKeys.insert(MenuPath.key(itemPath)).inserted {
                    // A duplicate path is a hidden alternate (the ⌥ variant); keep the first.
                    entries.append(MenuItemEntry(path: itemPath, shortcut: info.shortcut, isChecked: info.isChecked))
                }
            }
        }

        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        let summary = "pid \(pid): \(entries.count) menu items in \(elapsedMs)ms"
        if Date() >= deadline {
            log.warning("\(summary, privacy: .public) (stopped at the time budget)")
        } else {
            log.debug("\(summary, privacy: .public)")
        }
        return entries
    }

    // MARK: - Press

    private static func pressItem(at path: [String], pid: pid_t) -> MenuPressOutcome {
        guard var container = menuBar(of: pid) else { return .notFound }
        for (depth, title) in path.enumerated() {
            let isItem = depth == path.count - 1
            guard let found = match(title, in: children(of: container), wantSubmenu: !isItem) else {
                return .notFound
            }
            if let submenu = found.info.submenu, !isItem {
                container = submenu
                continue
            }
            guard found.info.isEnabled else { return .disabled }
            let result = AXUIElementPerformAction(found.element, kAXPressAction as CFString)
            switch result {
            case .success:
                return .pressed
            case .cannotComplete:
                // The app didn't reply within the messaging timeout — typically the
                // item opened a modal dialog. The press itself went through.
                log.debug("Press of '\(MenuPath.key(path), privacy: .public)' timed out waiting for a reply")
                return .pressed
            default:
                log.error("Press of '\(MenuPath.key(path), privacy: .public)' failed: AXError \(result.rawValue)")
                return .failed(result)
            }
        }
        return .notFound
    }

    /// The item titled `title`. Menus can hold same-titled items (hidden ⌥ alternates),
    /// so an exact, enabled match wins; then exact but disabled; then loose matches.
    private static func match(
        _ title: String,
        in items: [AXUIElement],
        wantSubmenu: Bool
    ) -> (element: AXUIElement, info: ItemInfo)? {
        let wanted = MenuPath.normalized(title)
        var best: (element: AXUIElement, info: ItemInfo, rank: Int)?
        for item in items {
            guard let info = itemInfo(of: item), (info.submenu != nil) == wantSubmenu else { continue }
            let isExact = info.title == title
            guard isExact || MenuPath.normalized(info.title) == wanted else { continue }
            let rank = (isExact ? 0 : 2) + (info.isEnabled ? 0 : 1)
            if rank == 0 {
                return (item, info)
            }
            if rank < best?.rank ?? .max {
                best = (item, info, rank)
            }
        }
        return best.map { ($0.element, $0.info) }
    }

    // MARK: - AX access

    /// The attributes read per item, fetched in a single round trip.
    private static let itemAttributes = [
        kAXTitleAttribute,
        kAXEnabledAttribute,
        kAXChildrenAttribute,
        kAXMenuItemCmdCharAttribute,
        kAXMenuItemCmdVirtualKeyAttribute,
        kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemMarkCharAttribute,
    ]

    private struct ItemInfo {
        let title: String
        let isEnabled: Bool
        let submenu: AXUIElement?
        let shortcut: String?
        let isChecked: Bool
    }

    private static func itemInfo(of item: AXUIElement) -> ItemInfo? {
        var valuesRef: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(item, itemAttributes as CFArray, [], &valuesRef) == .success,
              let values = valuesRef as? [AnyObject], values.count == itemAttributes.count
        else {
            return nil
        }
        // A missing attribute comes back as an AXValue error placeholder, which
        // fails these casts.
        let submenu = (values[2] as? [AXUIElement])?.first
        let mark = values[6] as? String ?? ""
        return ItemInfo(
            title: (values[0] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: values[1] as? Bool ?? true,
            submenu: submenu.map(withTimeout),
            shortcut: MenuShortcut.format(
                character: values[3] as? String,
                virtualKey: values[4] as? Int,
                modifiers: values[5] as? Int ?? 0
            ),
            isChecked: !mark.isEmpty
        )
    }

    private static func menuBar(of pid: pid_t) -> AXUIElement? {
        let app = withTimeout(AXUIElementCreateApplication(pid))
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return withTimeout(unsafeDowncast(ref, to: AXUIElement.self))
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement]
        else {
            return []
        }
        return children.map(withTimeout)
    }

    /// The timeout is stored per element reference (a local call, no round trip),
    /// so every element is given it before it's queried.
    private static func withTimeout(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }
}

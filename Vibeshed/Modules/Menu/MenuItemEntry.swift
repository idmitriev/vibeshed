import Foundation

/// One clickable (enabled, leaf) item in an app's menu bar.
struct MenuItemEntry: Sendable, Equatable {
    /// Titles from the top-level menu down to the item: `["File", "Open Recent", "notes.txt"]`.
    let path: [String]
    /// The item's keyboard shortcut as the menu draws it ("⇧⌘T"), if it has one.
    let shortcut: String?
    /// The item carries a mark (usually a checkmark): the setting it toggles is on.
    let isChecked: Bool

    var title: String {
        path.last ?? ""
    }

    /// The menus leading to the item: "View › Text Encoding".
    var location: String {
        MenuPath.display(path.dropLast())
    }

    /// "View › Text Encoding · ⌘T": where the item lives, plus its shortcut.
    var subtitle: String {
        shortcut.map { "\(location) · \($0)" } ?? location
    }

    var key: String {
        MenuPath.key(path)
    }
}

/// Menu paths double as action IDs (`menu/File > New Tab`), written the way menu
/// paths usually are, so keybindings and aliases can name an item by hand.
enum MenuPath {
    static let separator = " > "

    static func key(_ path: [String]) -> String {
        path.joined(separator: separator)
    }

    /// Titles named by `key`; nil unless it names an item inside a menu (a top-level
    /// menu plus at least one item).
    static func parse(_ key: String) -> [String]? {
        let path = key.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard path.count >= 2, !path.contains(where: \.isEmpty) else { return nil }
        return path
    }

    static func display(_ path: some Sequence<String>) -> String {
        path.joined(separator: " › ")
    }

    /// Loose form for titles typed by hand: case-insensitive, with the trailing
    /// ellipsis optional ("Save As…", "save as...", "Save As" all match).
    static func normalized(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespaces)
        if result.hasSuffix("…") {
            result.removeLast()
        } else if result.hasSuffix("...") {
            result.removeLast(3)
        }
        return result.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

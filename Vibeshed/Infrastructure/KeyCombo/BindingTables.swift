import CoreGraphics

/// The lookup tables `EventTapHandler` consults on every event, built from a
/// `ResolvedBindingSet`. Rebinding builds a fresh value and swaps it in whole
/// under the handler's lock.
struct BindingTables {
    var standard: [StandardKey: BindingSlot] = [:]
    var capsLock: [UInt16: BindingSlot] = [:]
    var space: [UInt16: BindingSlot] = [:]
    var tab: [UInt16: BindingSlot] = [:]
    var mouse: [MouseKey: BindingSlot] = [:]
    /// Remap targets keyed by app bundle ID; "" holds the global remap.
    var standardRemaps: [StandardKey: [String: RemapTarget]] = [:]
    var tabRemaps: [UInt16: [String: RemapTarget]] = [:]
    var mouseRemaps: [MouseKey: RemapTarget] = [:]

    init() {}

    init(_ resolved: ResolvedBindingSet) {
        for binding in resolved.standard + resolved.capsLock + resolved.space + resolved.tab + resolved.mouse {
            add(binding)
        }
        for remap in resolved.remaps + resolved.tabRemaps {
            add(remap)
        }
        for remap in resolved.mouseRemaps {
            let key = MouseKey(button: remap.button, modifiers: remap.modifiers)
            mouseRemaps[key] = RemapTarget(keyCode: remap.toKeyCode, modifiers: remap.toModifiers)
            Log.keybindings.debug(
                "  mouseRemap \(remap.rawFrom, privacy: .public) → \(remap.rawTo, privacy: .public)"
            )
        }
    }

    /// Entry counts per table, for the rebind log line.
    var summary: String {
        "\(standard.count)/\(capsLock.count)/\(space.count)/\(tab.count)/\(mouse.count)"
            + "+\(standardRemaps.count)rmp+\(tabRemaps.count)trmp+\(mouseRemaps.count)mrmp"
    }

    private mutating func add(_ binding: ResolvedBinding) {
        let action = binding.actionID.rawValue
        let combo = binding.rawCombo
        let entry: String
        switch binding.comboType {
        case let .standard(keyCode, modifiers):
            standard[StandardKey(keyCode: keyCode, modifiers: modifiers), default: BindingSlot()].assign(binding)
            let scope = binding.app ?? "global"
            entry = "std key=\(keyCode) fl=\(modifiers.rawValue) → \(action) [\(scope)]"
        case let .capsLockModifier(keyCode):
            capsLock[keyCode, default: BindingSlot()].assign(binding)
            entry = "capslock key=\(keyCode) → \(action) (\(combo))"
        case let .spaceModifier(keyCode):
            space[keyCode, default: BindingSlot()].assign(binding)
            entry = "space key=\(keyCode) → \(action) (\(combo))"
        case let .tabModifier(keyCode):
            tab[keyCode, default: BindingSlot()].assign(binding)
            entry = "tab key=\(keyCode) → \(action) (\(combo))"
        case let .mouseButton(button, modifiers):
            mouse[MouseKey(button: button, modifiers: modifiers), default: BindingSlot()].assign(binding)
            entry = "mouse btn=\(button) flags=\(modifiers.rawValue) → \(action) (\(combo))"
        }
        Log.keybindings.debug("  \(entry, privacy: .public)")
    }

    /// Standard and tab remaps; other source kinds are rejected when the config is resolved.
    private mutating func add(_ remap: ResolvedRemap) {
        let target = RemapTarget(keyCode: remap.toKeyCode, modifiers: remap.toModifiers)
        let appKey = remap.app ?? ""
        switch remap.fromType {
        case let .standard(keyCode, modifiers):
            standardRemaps[StandardKey(keyCode: keyCode, modifiers: modifiers), default: [:]][appKey] = target
            let mapping = "\(remap.rawFrom) → \(remap.rawTo) [\(remap.app ?? "global")]"
            Log.keybindings.debug("  remap \(mapping, privacy: .public)")
        case let .tabModifier(keyCode):
            tabRemaps[keyCode, default: [:]][appKey] = target
        default:
            break
        }
    }
}

/// The action bound to one trigger, globally and per app.
struct BindingSlot {
    var global: ActionID?
    var appSpecific: [String: ActionID] = [:]

    func resolve(focusedApp: String) -> ActionID? {
        appSpecific[focusedApp] ?? global
    }

    mutating func assign(_ binding: ResolvedBinding) {
        if let app = binding.app {
            appSpecific[app] = binding.actionID
        } else {
            global = binding.actionID
        }
    }
}

struct RemapTarget: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: CGEventFlags
}

struct StandardKey: Hashable {
    let keyCode: UInt16
    let modifiers: CGEventFlags

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }
}

struct MouseKey: Hashable {
    let button: Int
    let modifiers: CGEventFlags

    func hash(into hasher: inout Hasher) {
        hasher.combine(button)
        hasher.combine(modifiers.rawValue)
    }
}

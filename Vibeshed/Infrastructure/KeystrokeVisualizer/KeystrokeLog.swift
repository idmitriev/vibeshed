import Foundation

/// One bubble in the keystroke overlay.
struct KeystrokeChip: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A run of plain typing.
        case typing
        /// A chord or special key Vibeshed let through.
        case combo
        /// A Vibeshed keybinding fired this action.
        case binding(ActionID)
        /// A Vibeshed remap sent `target` instead.
        case remap(target: String)
    }

    let id: Int
    let kind: Kind
    var text: String
    /// How many times the same chord was pressed in a row.
    var count = 1
    /// The bound action's title, once resolved.
    var caption: String?
    var updatedAt: Date

    var isVibeshed: Bool {
        switch kind {
        case .binding, .remap: true
        case .typing, .combo: false
        }
    }
}

/// The overlay's recent keystrokes. Plain typing runs together in one chip, a
/// chord pressed again bumps its count, anything else starts a new chip.
struct KeystrokeLog {
    static let maxChips = 4
    /// A keystroke this soon after the last one may join its chip.
    static let mergeWindow: TimeInterval = 1.5
    static let maxTypingLength = 28

    private(set) var chips: [KeystrokeChip] = []
    private var nextID = 0

    /// Returns the chip now showing `keystroke`.
    @discardableResult
    mutating func record(_ keystroke: KeystrokeEvent, at now: Date) -> KeystrokeChip {
        let joinsLast = chips.last.map { now.timeIntervalSince($0.updatedAt) < Self.mergeWindow } ?? false

        if let typed = KeystrokeFormatter.typedText(for: keystroke) {
            if joinsLast, var last = chips.last, last.kind == .typing {
                last.text = Self.trimmed(last.text + typed)
                last.updatedAt = now
                return replaceLast(with: last)
            }
            return append(kind: .typing, text: typed, at: now)
        }

        let kind: KeystrokeChip.Kind = switch keystroke.outcome {
        case .passedThrough: .combo
        case let .binding(actionID): .binding(actionID)
        case let .remap(target):
            .remap(target: KeystrokeFormatter.comboLabel(keyCode: target.keyCode, modifiers: target.modifiers))
        }
        let text = KeystrokeFormatter.comboLabel(for: keystroke)
        if joinsLast, var last = chips.last, last.kind == kind, last.text == text {
            last.count += 1
            last.updatedAt = now
            return replaceLast(with: last)
        }
        return append(kind: kind, text: text, at: now)
    }

    /// Drops the chip unless a keystroke joined it after `date`.
    mutating func expire(_ id: Int, ifUnchangedSince date: Date) {
        chips.removeAll { $0.id == id && $0.updatedAt <= date }
    }

    mutating func setCaption(_ caption: String, for actionID: ActionID) {
        for index in chips.indices where chips[index].kind == .binding(actionID) {
            chips[index].caption = caption
        }
    }

    mutating func removeAll() {
        chips.removeAll()
    }

    private mutating func append(kind: KeystrokeChip.Kind, text: String, at now: Date) -> KeystrokeChip {
        let chip = KeystrokeChip(id: nextID, kind: kind, text: text, updatedAt: now)
        nextID += 1
        chips.append(chip)
        if chips.count > Self.maxChips {
            chips.removeFirst(chips.count - Self.maxChips)
        }
        return chip
    }

    private mutating func replaceLast(with chip: KeystrokeChip) -> KeystrokeChip {
        chips[chips.count - 1] = chip
        return chip
    }

    private static func trimmed(_ text: String) -> String {
        guard text.count > maxTypingLength else { return text }
        return "…" + text.suffix(maxTypingLength - 1)
    }
}

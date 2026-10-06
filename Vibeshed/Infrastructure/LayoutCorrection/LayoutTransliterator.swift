import Carbon.HIToolbox
import Foundation

@MainActor
@Observable
final class LayoutTransliterator {
    /// Per input-source mapping: nonLatinChar → latinChar (both unshifted and shifted).
    private var mappingTables: [String: [Character: Character]] = [:]
    /// Localized name per source ID for the correction hint.
    private var sourceNames: [String: String] = [:]
    /// The Latin layout the tables map onto; rebuilt when the user picks another one.
    private var latinSourceID: String?
    private var isEnabled: Bool = true
    private var inputSourceObserver: NSObjectProtocol?
    private var selectedSourceObserver: NSObjectProtocol?

    private let configManager: ConfigManager
    private let eventBus: EventBus

    init(configManager: ConfigManager, eventBus: EventBus) {
        self.configManager = configManager
        self.eventBus = eventBus
    }

    func start() {
        reloadConfig()
        buildMappingTables()

        // Rebuild tables when the set of installed input sources changes.
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buildMappingTables()
            }
        }

        // Switching between enabled Latin layouts (ABC ↔ Dvorak) moves the target.
        selectedSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildIfLatinTargetChanged()
            }
        }

        // Reload config on changes.
        Task { [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                if case .configReloaded = event {
                    self.reloadConfig()
                }
            }
        }
    }

    // MARK: - Transliteration

    /// Latin readings of a query typed with the wrong input source, most likely first.
    /// Empty when the query looks Latin already or correction is disabled.
    ///
    /// Matches on the characters themselves rather than only the active source, so a
    /// query still corrects after the source changed (a mid-query switch, or macOS
    /// auto-switching per window). Input methods (Korean, Japanese, Zhuyin) have no
    /// key table and are reversed by `InputMethodTransliteration`.
    func corrections(for query: String) -> [LayoutCorrectionHint] {
        guard isEnabled, !query.isEmpty, !query.allSatisfy(\.isASCII) else { return [] }

        let imeCandidates = InputMethodTransliteration.candidates(for: query)
        if !imeCandidates.isEmpty {
            return imeCandidates.compactMap { hint(query, $0.text, $0.language) }
        }

        let currentID = TISCopyCurrentKeyboardInputSource().map { inputSourceID($0.takeRetainedValue()) }
        guard let (sourceID, corrected) = Self.bestMapping(
            for: query, tables: mappingTables, preferring: currentID
        ) else { return [] }
        return hint(query, corrected, sourceNames[sourceID] ?? "Unknown").map { [$0] } ?? []
    }

    /// The layout table that maps every non-ASCII character of `query`, preferring
    /// `preferredID` (the active source) when several do — Russian and Ukrainian
    /// share most letters.
    nonisolated static func bestMapping(
        for query: String,
        tables: [String: [Character: Character]],
        preferring preferredID: String?
    ) -> (sourceID: String, corrected: String)? {
        let foreign = query.filter { !$0.isASCII && !$0.isWhitespace }
        guard !foreign.isEmpty else { return nil }

        let covering = tables.filter { _, table in foreign.allSatisfy { table[$0] != nil } }
        guard let sourceID = covering[preferredID ?? ""] != nil
            ? preferredID
            : covering.keys.min(),
            let table = covering[sourceID]
        else { return nil }
        return (sourceID, String(query.map { table[$0] ?? $0 }))
    }

    private func hint(_ query: String, _ corrected: String, _ layoutName: String) -> LayoutCorrectionHint? {
        guard corrected != query else { return nil }
        let correction = "'\(query)' → '\(corrected)' (\(layoutName))"
        Log.layout.debug("Layout correction: \(correction, privacy: .public)")
        return LayoutCorrectionHint(originalQuery: query, correctedQuery: corrected, sourceLayoutName: layoutName)
    }

    // MARK: - Config

    private func reloadConfig() {
        isEnabled = configManager.config.layoutCorrection.enabled
        Log.layout.debug("Layout correction enabled: \(self.isEnabled)")
    }

    // MARK: - Mapping Table Construction

    /// Runs on every input source switch, so it only rebuilds when the Latin layout
    /// itself changed — not on the common ABC ↔ Russian switches.
    private func rebuildIfLatinTargetChanged() {
        guard let latin = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              inputSourceID(latin) != latinSourceID
        else { return }
        buildMappingTables()
    }

    private func buildMappingTables() {
        mappingTables.removeAll()
        sourceNames.removeAll()

        let conditions = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource,
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?
            .takeRetainedValue() as? [TISInputSource]
        else {
            Log.layout.warning("Failed to enumerate keyboard input sources")
            return
        }

        // Transliterate TO the Latin layout the user actually types with (ABC, Dvorak…).
        guard let latinSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
            ?? sourceList.first(where: { isASCIICapable($0) })
        else {
            Log.layout.info("No ASCII-capable keyboard layout found, layout correction disabled")
            return
        }

        latinSourceID = inputSourceID(latinSource)
        let latinUnshifted = keycodeToCharMap(for: latinSource, shifted: false)
        let latinShifted = keycodeToCharMap(for: latinSource, shifted: true)

        // For each non-Latin source, build char→char mapping.
        for source in sourceList {
            guard !isASCIICapable(source) else { continue }

            let sid = inputSourceID(source)
            let name = localizedName(source)
            sourceNames[sid] = name

            let srcUnshifted = keycodeToCharMap(for: source, shifted: false)
            let srcShifted = keycodeToCharMap(for: source, shifted: true)

            var charMapping: [Character: Character] = [:]

            // Map unshifted characters.
            for keyCode in UInt16(0) ... 127 {
                if let srcChar = srcUnshifted[keyCode],
                   let latChar = latinUnshifted[keyCode],
                   srcChar != latChar
                {
                    charMapping[srcChar] = latChar
                }
            }

            // Map shifted characters.
            for keyCode in UInt16(0) ... 127 {
                if let srcChar = srcShifted[keyCode],
                   let latChar = latinShifted[keyCode],
                   srcChar != latChar
                {
                    charMapping[srcChar] = latChar
                }
            }

            if !charMapping.isEmpty {
                mappingTables[sid] = charMapping
                Log.layout
                    .debug("Built mapping table for '\(name, privacy: .public)' with \(charMapping.count) entries")
            }
        }

        Log.layout.info("Layout correction: \(self.mappingTables.count) non-Latin layout(s) mapped")
    }

    /// Build a keycode → character map for a given input source and modifier state.
    private func keycodeToCharMap(for source: TISInputSource, shifted: Bool) -> [UInt16: Character] {
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue() as Data
        let keyLayoutPtr = (layoutData as NSData).bytes.assumingMemoryBound(to: UCKeyboardLayout.self)

        let modifierState: UInt32 = shifted ? (UInt32(shiftKey >> 8) & 0xFF) : 0
        let kbdType = UInt32(LMGetKbdType())

        var map: [UInt16: Character] = [:]
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        var deadKeyState: UInt32 = 0

        for keyCode in UInt16(0) ... 127 {
            deadKeyState = 0
            let status = UCKeyTranslate(
                keyLayoutPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                kbdType,
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )
            if status == noErr, actualLength > 0 {
                let str = String(utf16CodeUnits: chars, count: actualLength)
                if let ch = str.first, !ch.isNewline, ch != "\0" {
                    map[keyCode] = ch
                }
            }
        }
        return map
    }

    // MARK: - TIS Helpers

    private func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
        else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }

    private func inputSourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func localizedName(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return "Unknown"
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

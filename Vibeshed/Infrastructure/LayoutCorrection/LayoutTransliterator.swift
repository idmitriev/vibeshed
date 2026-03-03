import Carbon.HIToolbox
import Foundation

@MainActor
@Observable
final class LayoutTransliterator {
    /// Per input-source mapping: nonLatinChar → latinChar (both unshifted and shifted).
    private var mappingTables: [String: [Character: Character]] = [:]
    /// Localized name per source ID for the correction hint.
    private var sourceNames: [String: String] = [:]
    private var isEnabled: Bool = true

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
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buildMappingTables()
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

    /// Attempts to transliterate the query from the current non-Latin input source to Latin.
    /// Returns `nil` if the current source is already Latin, disabled, or no mapping exists.
    func transliterate(_ query: String) -> LayoutCorrectionHint? {
        guard isEnabled, !query.isEmpty else { return nil }

        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        // If current source is ASCII-capable (Latin), no correction needed.
        if isASCIICapable(currentSource) { return nil }

        let sourceID = inputSourceID(currentSource)
        guard let mapping = mappingTables[sourceID] else { return nil }

        var corrected: [Character] = []
        var anyMapped = false
        for ch in query {
            if let mapped = mapping[ch] {
                corrected.append(mapped)
                anyMapped = true
            } else {
                corrected.append(ch)
            }
        }

        guard anyMapped else { return nil }

        let correctedQuery = String(corrected)
        guard correctedQuery != query else { return nil }

        let layoutName = sourceNames[sourceID] ?? "Unknown"
        Log.layout.debug(
            "Layout correction: '\(query, privacy: .public)' → '\(correctedQuery, privacy: .public)' (\(layoutName, privacy: .public))"
        )

        return LayoutCorrectionHint(
            originalQuery: query,
            correctedQuery: correctedQuery,
            sourceLayoutName: layoutName
        )
    }

    // MARK: - Config

    private func reloadConfig() {
        isEnabled = configManager.config.layoutCorrection.enabled
        Log.layout.debug("Layout correction enabled: \(self.isEnabled)")
    }

    // MARK: - Mapping Table Construction

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

        // Find the primary ASCII-capable (Latin) source to transliterate TO.
        guard let latinSource = sourceList.first(where: { isASCIICapable($0) }) else {
            Log.layout.info("No ASCII-capable keyboard layout found, layout correction disabled")
            return
        }

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
                   srcChar != latChar {
                    charMapping[srcChar] = latChar
                }
            }

            // Map shifted characters.
            for keyCode in UInt16(0) ... 127 {
                if let srcChar = srcShifted[keyCode],
                   let latChar = latinShifted[keyCode],
                   srcChar != latChar {
                    charMapping[srcChar] = latChar
                }
            }

            if !charMapping.isEmpty {
                mappingTables[sid] = charMapping
                Log.layout.debug("Built mapping table for '\(name, privacy: .public)' with \(charMapping.count) entries")
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
        var actualLength: Int = 0
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

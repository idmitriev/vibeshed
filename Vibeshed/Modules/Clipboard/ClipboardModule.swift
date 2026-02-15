import AppKit
import Foundation
import OSLog

actor ClipboardModule: ModuleConfigurable {
    let id = "clipboard"
    let displayName = "Clipboard"
    let iconName = "doc.on.clipboard"
    var isEnabled = true

    typealias Config = ClipboardConfig
    static var defaultConfig: Config? { .init() }

    private var config: ClipboardConfig = .init()
    private var context: ModuleContext?
    private var monitorToken: ClipboardManager.MonitorToken?
    private var history: ClipboardHistory?
    private let log = Log.module("clipboard")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        let hist = await MainActor.run { ClipboardHistory() }
        self.history = hist
        await hist.updateConfig(
            maxItems: config.maxItems,
            excludePatterns: config.excludePatterns
        )
        await startMonitoring()
        let maxItems = self.config.maxItems
        let interval = self.config.pollingInterval
        log.info("Clipboard module initialized (maxItems: \(maxItems, privacy: .public), interval: \(interval, privacy: .public)s)")
    }

    func teardown() async {
        let token = monitorToken
        await MainActor.run { token?.invalidate() }
        monitorToken = nil
        log.info("Clipboard module torn down")
    }

    func configDidUpdate(_ config: ClipboardConfig) async {
        let oldInterval = self.config.pollingInterval
        self.config = config
        let hist = history
        await MainActor.run {
            hist?.updateConfig(
                maxItems: config.maxItems,
                excludePatterns: config.excludePatterns
            )
        }
        if config.pollingInterval != oldInterval {
            let token = monitorToken
            await MainActor.run { token?.invalidate() }
            await startMonitoring()
            log.debug("Polling interval changed to \(config.pollingInterval, privacy: .public)s")
        }
    }

    static func validate(_ config: ClipboardConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxItems < 1 || config.maxItems > 10000 {
            errors.append("maxItems must be between 1 and 10000")
        }
        if config.pollingInterval < 0.1 || config.pollingInterval > 5.0 {
            errors.append("pollingInterval must be between 0.1 and 5.0 seconds")
        }
        if let patterns = config.excludePatterns {
            for (index, pattern) in patterns.enumerated() {
                do {
                    _ = try NSRegularExpression(pattern: pattern)
                } catch {
                    errors.append("excludePatterns[\(index)] is invalid regex: \(error.localizedDescription)")
                }
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let cfg = config
        let hist = history
        let historyItems = await MainActor.run { hist?.items ?? [] }
        var actions: [any Action] = buildHistoryActions(
            items: historyItems,
            config: cfg
        )

        if cfg.showClearAction, !historyItems.isEmpty {
            actions.append(buildClearAction())
        }

        if let enabled = cfg.enabledActions {
            actions = actions.filter { action in
                let raw = action.id.rawValue
                guard let dotIndex = raw.firstIndex(of: ".") else { return true }
                let name = String(raw[raw.index(after: dotIndex)...])
                return enabled.contains(name)
            }
        }

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() async {
        let eventBus = context?.eventBus
        let hist = history
        let interval = config.pollingInterval

        let token = await MainActor.run {
            ClipboardManager.startMonitoring(interval: interval) { content, sourceApp in
                hist?.addItem(content: content, sourceApp: sourceApp)
                Task {
                    await eventBus?.publish(.moduleActionsChanged(moduleID: "clipboard"))
                }
            }
        }
        self.monitorToken = token
    }

    // MARK: - Build Actions

    private func buildHistoryActions(
        items: [ClipboardItem],
        config: ClipboardConfig
    ) -> [ClipboardAction] {
        let pasteOnSelect = config.pasteOnSelect
        return items.enumerated().map { index, item in
            let truncatedTitle = truncate(item.content, maxLength: 80)
            let subtitle = "\(relativeTime(from: item.timestamp)) \u{2022} \(item.contentType.rawValue)"
            let iconName = iconForContentType(item.contentType)
            let relevance = max(0.3, 0.95 - Double(index) * 0.005)
            let contentWords = item.content
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .prefix(10)
                .map { $0.lowercased() }

            let itemContent = item.content
            return ClipboardAction(
                id: ActionID(module: "clipboard", name: "item.\(item.id)"),
                title: truncatedTitle,
                subtitle: subtitle,
                iconName: iconName,
                relevanceScore: relevance,
                keywords: ["clipboard", "paste", "copy", "history"] + contentWords,
                contentPreview: itemContent,
                contentType: item.contentType,
                timestamp: item.timestamp
            ) { _ in
                await MainActor.run {
                    ClipboardManager.writeToPasteboard(itemContent)
                    if pasteOnSelect {
                        ClipboardManager.pasteFromPasteboard()
                    }
                }
                return .dismiss
            }
        }
    }

    private func buildClearAction() -> ClipboardAction {
        let hist = history
        let eventBus = context?.eventBus
        return ClipboardAction(
            id: ActionID(module: "clipboard", name: "clear"),
            title: "Clear Clipboard History",
            subtitle: "Remove all items from clipboard history",
            iconName: "trash",
            relevanceScore: 0.3,
            keywords: ["clear", "clipboard", "history", "delete", "remove"]
        ) { _ in
            await MainActor.run { hist?.clear() }
            Task { await eventBus?.publish(.moduleActionsChanged(moduleID: "clipboard")) }
            return .showResult(
                title: "Clipboard Cleared",
                body: "All clipboard history items have been removed"
            )
        }
    }

    // MARK: - Helpers

    private func truncate(_ str: String, maxLength: Int) -> String {
        let firstLine = str.prefix(while: { $0 != "\n" && $0 != "\r" })
        if firstLine.count <= maxLength { return String(firstLine) }
        return String(firstLine.prefix(maxLength - 1)) + "\u{2026}"
    }

    private func iconForContentType(_ type: ClipboardContentType) -> String {
        switch type {
        case .text: "doc.plaintext"
        case .url: "link"
        case .filePath: "folder"
        }
    }

    private func relativeTime(from date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        switch elapsed {
        case ..<10: return "just now"
        case ..<60: return "\(Int(elapsed))s ago"
        case ..<3600: return "\(Int(elapsed / 60))m ago"
        case ..<86400: return "\(Int(elapsed / 3600))h ago"
        case ..<172_800: return "yesterday"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

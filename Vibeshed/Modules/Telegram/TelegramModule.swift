import AppKit
import Foundation
import OSLog

private let telegramBundleID = "ru.keepcoder.Telegram"

actor TelegramModule: ModuleConfigurable {
    let id = "telegram"
    let displayName = "Telegram"
    let iconName = "paperplane.fill"
    var isEnabled = true

    typealias Config = TelegramConfig
    static var defaultConfig: Config? { .init() }

    private var config: TelegramConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("telegram")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Telegram module initialized (\(self.config.chats.count, privacy: .public) chats configured)")
    }

    func configDidUpdate(_ config: TelegramConfig) async {
        self.config = config
        log.debug("Config updated (\(config.chats.count, privacy: .public) chats)")
    }

    static func validate(
        _ config: TelegramConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        var seenNames = Set<String>()

        for (index, entry) in config.chats.enumerated() {
            let name = entry.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if name.isEmpty {
                errors.append(
                    "Chat at index \(index) has an empty name"
                )
            }
            if entry.username == nil && entry.phone == nil {
                errors.append(
                    "Chat '\(entry.name)' needs a username or phone"
                )
            }
            if let username = entry.username,
               username.trimmingCharacters(
                   in: .whitespacesAndNewlines
               ).isEmpty {
                errors.append(
                    "Chat '\(entry.name)' has an empty username"
                )
            }
            if let phone = entry.phone,
               phone.trimmingCharacters(
                   in: .whitespacesAndNewlines
               ).isEmpty {
                errors.append(
                    "Chat '\(entry.name)' has an empty phone"
                )
            }
            if seenNames.contains(name) {
                errors.append("Duplicate chat name: '\(name)'")
            }
            seenNames.insert(name)
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Actions

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        let actions = buildActions()
        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    private func buildActions() -> [TelegramAction] {
        let enabled = config.enabledActions
        var actions: [TelegramAction] = []

        actions.append(contentsOf: buildChatActions())

        if config.showSavedMessages {
            actions.append(buildSavedMessagesAction())
        }

        if config.showLaunchAction {
            actions.append(buildLaunchAction())
        }

        actions.append(buildSettingsAction())

        if let enabled {
            return actions.filter { action in
                enabled.contains(actionSuffix(action.id))
            }
        }
        return actions
    }

    // MARK: - Chat Actions

    private func buildChatActions() -> [TelegramAction] {
        config.chats.map { entry in
            let chatType = entry.type ?? .chat
            let subtitle = chatSubtitle(entry)
            let keywords = (entry.keywords ?? [])
                + ["telegram", entry.name.lowercased()]

            return TelegramAction(
                id: ActionID(
                    module: "telegram",
                    name: "chat.\(stableID(entry.name))"
                ),
                title: entry.name,
                subtitle: subtitle,
                iconName: entry.icon,
                relevanceScore: 0.8,
                keywords: keywords,
                telegramItemType: .chat,
                chatType: chatType
            ) { _ in
                let url = Self.resolveURL(for: entry)
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
                return .dismiss
            }
        }
    }

    private func chatSubtitle(
        _ entry: TelegramChatEntry
    ) -> String {
        if let username = entry.username {
            return "@\(username)"
        }
        if let phone = entry.phone {
            return phone
        }
        return ""
    }

    // MARK: - Utility Actions

    private func buildSavedMessagesAction() -> TelegramAction {
        TelegramAction(
            id: ActionID(module: "telegram", name: "savedMessages"),
            title: "Saved Messages",
            subtitle: "Open Telegram Saved Messages",
            iconName: "bookmark.fill",
            relevanceScore: 0.6,
            keywords: ["telegram", "saved", "bookmarks"],
            telegramItemType: .utility
        ) { _ in
            if let url = URL(string: "tg://resolve?domain=me") {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
            return .dismiss
        }
    }

    private func buildLaunchAction() -> TelegramAction {
        let isRunning = Self.isTelegramRunning()
        let title = isRunning ? "Focus Telegram" : "Open Telegram"
        let subtitle = isRunning ? "Bring to front" : "Launch Telegram"

        return TelegramAction(
            id: ActionID(module: "telegram", name: "launch"),
            title: title,
            subtitle: subtitle,
            iconName: "paperplane.fill",
            relevanceScore: 0.5,
            keywords: ["telegram", "open", "launch", "focus"],
            telegramItemType: .utility
        ) { _ in
            DispatchQueue.main.async {
                let apps = NSRunningApplication
                    .runningApplications(
                        withBundleIdentifier: telegramBundleID
                    )
                if let app = apps.first {
                    app.activate()
                } else {
                    let url = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: telegramBundleID
                    )
                    if let url {
                        NSWorkspace.shared.openApplication(
                            at: url,
                            configuration: .init()
                        )
                    }
                }
            }
            return .dismiss
        }
    }

    private func buildSettingsAction() -> TelegramAction {
        TelegramAction(
            id: ActionID(module: "telegram", name: "settings"),
            title: "Telegram Settings",
            subtitle: "Open Telegram settings",
            iconName: "gearshape.fill",
            relevanceScore: 0.4,
            keywords: ["telegram", "settings", "preferences"],
            telegramItemType: .utility
        ) { _ in
            if let url = URL(string: "tg://settings") {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
            return .dismiss
        }
    }

    // MARK: - Helpers

    private static func resolveURL(
        for entry: TelegramChatEntry
    ) -> URL {
        if let username = entry.username {
            return URL(
                string: "tg://resolve?domain=\(username)"
            )!
        }
        if let phone = entry.phone {
            let cleaned = phone.replacingOccurrences(
                of: "+", with: ""
            )
            return URL(
                string: "tg://resolve?phone=\(cleaned)"
            )!
        }
        return URL(string: "tg://resolve?domain=me")!
    }

    private static func isTelegramRunning() -> Bool {
        !NSRunningApplication
            .runningApplications(
                withBundleIdentifier: telegramBundleID
            )
            .isEmpty
    }

    private func stableID(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }

    private func actionSuffix(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else {
            return raw
        }
        return String(raw[raw.index(after: dotIndex)...])
    }
}

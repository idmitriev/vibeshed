import AppKit
import Foundation
import OSLog

actor ZoomModule: ModuleConfigurable {
    let id = "zoom"
    let displayName = "Zoom"
    let iconName = "video.fill"
    var isEnabled = true

    typealias Config = ZoomConfig
    static var defaultConfig: Config? { .init() }

    private var config: ZoomConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("zoom")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info(
            "Zoom module initialized (\(self.config.meetings.count, privacy: .public) meetings configured)"
        )
    }

    func configDidUpdate(_ config: ZoomConfig) async {
        self.config = config
        log.debug("Config updated (\(config.meetings.count, privacy: .public) meetings)")
    }

    static func validate(
        _ config: ZoomConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        var seenNames = Set<String>()

        for (index, entry) in config.meetings.enumerated() {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                errors.append("Meeting at index \(index) has an empty name")
            }
            if entry.meetingId == nil && entry.link == nil {
                errors.append(
                    "Meeting '\(entry.name)' needs a meetingId or link"
                )
            }
            if let meetingId = entry.meetingId,
               meetingId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                errors.append("Meeting '\(entry.name)' has an empty meetingId")
            }
            if let link = entry.link {
                if ZoomManager.parseMeetingInput(link) == nil {
                    errors.append(
                        "Meeting '\(entry.name)' has an invalid link: \(link)"
                    )
                }
            }
            if seenNames.contains(name) {
                errors.append("Duplicate meeting name: '\(name)'")
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
        buildActions()
    }

    private func buildActions() -> [ZoomAction] {
        let enabled = config.enabledActions
        var actions: [ZoomAction] = []

        actions.append(contentsOf: buildMeetingActions())

        if config.showJoinAction {
            actions.append(buildJoinAction())
        }

        if config.showStartMeeting, config.personalMeetingId != nil {
            actions.append(buildStartPersonalAction())
        }

        if config.showLaunchAction {
            actions.append(buildLaunchAction())
        }

        if let enabled {
            return actions.filter { action in
                enabled.contains(actionSuffix(action.id))
            }
        }
        return actions
    }

    // MARK: - Meeting Actions

    private func buildMeetingActions() -> [ZoomAction] {
        config.meetings.compactMap { entry in
            guard let resolved = ZoomManager.resolve(entry) else { return nil }

            let subtitle = "Meeting ID: \(ZoomManager.formatMeetingId(resolved.meetingId))"
            let keywords = (entry.keywords ?? [])
                + ["zoom", "meeting", entry.name.lowercased()]

            return ZoomAction(
                id: ActionID(
                    module: "zoom",
                    name: "meeting.\(stableID(entry.name))"
                ),
                title: entry.name,
                subtitle: subtitle,
                iconName: entry.icon,
                relevanceScore: 0.8,
                keywords: keywords,
                zoomItemType: .meeting,
                meetingId: resolved.meetingId
            ) { _ in
                let url = ZoomManager.joinURL(
                    meetingId: resolved.meetingId,
                    password: resolved.password
                )
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
                return .dismiss
            }
        }
    }

    // MARK: - Join Action

    private func buildJoinAction() -> ZoomAction {
        ZoomAction(
            id: ActionID(module: "zoom", name: "join"),
            title: "Join Meeting",
            subtitle: "Enter a meeting ID or Zoom link",
            iconName: "phone.arrow.right",
            relevanceScore: 0.6,
            keywords: ["zoom", "join", "meeting", "call"],
            parameters: [
                ActionParameter(
                    id: "meetingInput",
                    label: "Meeting ID or Link",
                    type: .text(placeholder: "Meeting ID or Zoom link"),
                    isRequired: true
                ),
            ],
            zoomItemType: .utility
        ) { values in
            guard let input = values["meetingInput"] as? String,
                  let parsed = ZoomManager.parseMeetingInput(input)
            else {
                return .showResult(
                    title: "Invalid Input",
                    body: "Could not parse meeting ID or link."
                )
            }
            let url = ZoomManager.joinURL(
                meetingId: parsed.meetingId,
                password: parsed.password
            )
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
            return .dismiss
        }
    }

    // MARK: - Start Personal Meeting

    private func buildStartPersonalAction() -> ZoomAction {
        let personalId = config.personalMeetingId ?? ""

        return ZoomAction(
            id: ActionID(module: "zoom", name: "startPersonal"),
            title: "Start My Meeting",
            subtitle: "Start your personal Zoom meeting",
            iconName: "video.badge.plus",
            relevanceScore: 0.5,
            keywords: ["zoom", "start", "personal", "meeting", "new"],
            zoomItemType: .utility,
            meetingId: personalId
        ) { _ in
            let url = ZoomManager.startPersonalMeetingURL(meetingId: personalId)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
            return .dismiss
        }
    }

    // MARK: - Launch Action

    private func buildLaunchAction() -> ZoomAction {
        let isRunning = ZoomManager.isZoomRunning()
        let title = isRunning ? "Focus Zoom" : "Open Zoom"
        let subtitle = isRunning ? "Bring Zoom to front" : "Launch Zoom"

        return ZoomAction(
            id: ActionID(module: "zoom", name: "launch"),
            title: title,
            subtitle: subtitle,
            iconName: "video.fill",
            relevanceScore: 0.4,
            keywords: ["zoom", "open", "launch", "focus"],
            zoomItemType: .utility
        ) { _ in
            DispatchQueue.main.async {
                ZoomManager.focusOrLaunchZoom()
            }
            return .dismiss
        }
    }

    // MARK: - Helpers

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

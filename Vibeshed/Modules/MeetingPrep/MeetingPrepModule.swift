import AppKit
import EventKit
import Foundation
import OSLog

actor MeetingPrepModule: ModuleConfigurable {
    let id = "meetingPrep"
    let displayName = "Meeting Prep"
    let iconName = "clock.badge.checkmark"
    var isEnabled = true

    typealias Config = MeetingPrepConfig
    static var defaultConfig: Config? { .init() }

    static var requiredPermissions: Set<Permission> {
        [.accessibility, .screenRecording]
    }

    private var config: MeetingPrepConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("meetingPrep")
    private let windowManager = WindowManager()

    // Cache calendar events
    private var cachedEvents: [CalendarManager.CalendarEvent] = []
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 30

    // Track hidden windows for restore
    private var hiddenWindowIDs: [Int] = []

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Meeting Prep module initialized")
    }

    func configDidUpdate(_ config: MeetingPrepConfig) async {
        self.config = config
        cacheTimestamp = .distantPast
        log.debug(
            "Config updated (prepWindow: \(config.prepWindowMinutes, privacy: .public)m)"
        )
    }

    static func validate(
        _ config: MeetingPrepConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.prepWindowMinutes < 1 || config.prepWindowMinutes > 120 {
            errors.append(
                "prepWindowMinutes must be between 1 and 120"
            )
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Actions

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        guard CalendarManager.hasAccess else { return [] }
        refreshCacheIfNeeded()
        return buildActions()
    }

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(cacheTimestamp) > cacheTTL else {
            return
        }

        cachedEvents = CalendarManager.fetchEvents(
            lookaheadHours: 2,
            lookbehindMinutes: 5,
            excludedCalendars: nil,
            includedCalendars: nil,
            showAllDay: false,
            showDeclined: false
        )
        cacheTimestamp = now
    }

    private func buildActions() -> [MeetingPrepAction] {
        let enabled = config.enabledActions
        var actions: [MeetingPrepAction] = []

        let upcomingMeetings = findUpcomingMeetings()
        for meeting in upcomingMeetings {
            actions.append(contentsOf: buildPrepActions(for: meeting))
        }

        // Always offer hide distractions and restore
        actions.append(buildHideDistractionsAction())
        if !hiddenWindowIDs.isEmpty {
            actions.append(buildRestoreWindowsAction())
        }

        if let enabled {
            return actions.filter { action in
                enabled.contains(actionSuffix(action.id))
            }
        }
        return actions
    }

    // MARK: - Find Upcoming Meetings

    private func findUpcomingMeetings() -> [CalendarManager.CalendarEvent] {
        let now = Date()
        let prepWindow = Double(config.prepWindowMinutes) * 60

        return cachedEvents.filter { event in
            guard !event.isAllDay else { return false }
            let timeUntilStart = event.startDate.timeIntervalSince(now)
            // Show prep actions if meeting is happening now or starting within prep window
            return (timeUntilStart <= prepWindow && now < event.endDate)
        }
    }

    // MARK: - Per-Meeting Prep Actions

    private struct EventMeta {
        let stableID: String
        let timeLabel: String
        let relevance: Double
        let eventTitle: String
        let videoURL: URL?
        let videoType: VideoLinkType?
        let attendees: [String]?
        let startDate: Date
        let endDate: Date
        let calendarTitle: String
        let calendarColorHex: String
    }

    private func eventMeta(
        for event: CalendarManager.CalendarEvent
    ) -> EventMeta {
        let now = Date()
        let minutesUntil = event.startDate.timeIntervalSince(now) / 60
        let isHappening = minutesUntil <= 0 && now < event.endDate
        let videoLink = CalendarManager.detectVideoLink(
            url: event.url, location: event.location, notes: event.notes
        )
        let stableInput =
            "\(event.eventIdentifier)_\(event.startDate.timeIntervalSince1970)"
        return EventMeta(
            stableID: CalendarManager.stableID(stableInput),
            timeLabel: isHappening ? "now" : "in \(Int(max(1, minutesUntil)))m",
            relevance: isHappening ? 0.98 : (minutesUntil <= 5 ? 0.95 : 0.85),
            eventTitle: event.title,
            videoURL: videoLink?.url,
            videoType: videoLink?.type,
            attendees: event.attendeeNames.isEmpty ? nil : event.attendeeNames,
            startDate: event.startDate,
            endDate: event.endDate,
            calendarTitle: event.calendarTitle,
            calendarColorHex: event.calendarColorHex
        )
    }

    private func buildPrepActions(
        for event: CalendarManager.CalendarEvent
    ) -> [MeetingPrepAction] {
        let meta = eventMeta(for: event)
        var actions: [MeetingPrepAction] = []
        actions.append(
            buildMainPrepAction(event: event, meta: meta)
        )
        if let joinAction = buildJoinVideoAction(event: event, meta: meta) {
            actions.append(joinAction)
        }
        return actions
    }

    private func buildMainPrepAction(
        event: CalendarManager.CalendarEvent,
        meta: EventMeta
    ) -> MeetingPrepAction {
        let cfg = config
        let autoJoin = cfg.autoJoinVideo
        let videoURL = meta.videoURL
        let videoType = meta.videoType
        let eventTitle = meta.eventTitle
        let stableID = meta.stableID

        return MeetingPrepAction(
            id: ActionID(module: "meetingPrep", name: "prep.\(stableID)"),
            title: "Prepare: \(eventTitle)",
            subtitle: "Hide distractions\(videoURL != nil ? " & join call" : "") \u{2022} \(meta.timeLabel)",
            iconName: "clock.badge.checkmark",
            relevanceScore: meta.relevance,
            keywords: buildKeywords(event: event, extra: ["prepare", "meeting", "focus", "prep"]),
            actionType: .prepForMeeting,
            meetingTitle: eventTitle,
            startDate: meta.startDate,
            endDate: meta.endDate,
            attendeeNames: meta.attendees,
            videoLinkType: videoType,
            videoURL: videoURL,
            calendarName: meta.calendarTitle,
            calendarColorHex: meta.calendarColorHex
        ) { [weak self] _ in
            let hiddenCount = await self?.hideDistractingWindows(config: cfg) ?? 0
            if autoJoin, let videoURL {
                DispatchQueue.main.async { CalendarManager.openVideoLink(videoURL) }
            }
            return await self?.buildPrepResult(
                hiddenCount: hiddenCount, autoJoin: autoJoin,
                eventTitle: eventTitle, stableID: stableID,
                videoURL: videoURL, videoType: videoType
            ) ?? .dismiss
        }
    }

    private func buildPrepResult(
        hiddenCount: Int, autoJoin: Bool,
        eventTitle: String, stableID: String,
        videoURL: URL?, videoType: VideoLinkType?
    ) -> ActionResult {
        var resultActions: [any Action] = []

        if !autoJoin, let videoURL {
            resultActions.append(MeetingPrepAction(
                id: ActionID(module: "meetingPrep", name: "join.\(stableID)"),
                title: "Join: \(eventTitle)",
                subtitle: videoType.map { "\($0.rawValue.capitalized) call" } ?? "Video call",
                iconName: "video.fill",
                relevanceScore: 0.95,
                keywords: ["join", "video", "call"],
                actionType: .joinVideo,
                meetingTitle: eventTitle,
                videoLinkType: videoType,
                videoURL: videoURL
            ) { _ in
                DispatchQueue.main.async { CalendarManager.openVideoLink(videoURL) }
                return .dismiss
            })
        }

        if hiddenCount > 0 {
            resultActions.append(MeetingPrepAction(
                id: ActionID(module: "meetingPrep", name: "restoreAfterPrep.\(stableID)"),
                title: "Restore Windows",
                subtitle: "Un-minimize \(hiddenCount) hidden windows",
                iconName: "macwindow.on.rectangle",
                relevanceScore: 0.8,
                keywords: ["restore", "windows", "show"],
                actionType: .restoreWindows
            ) { [weak self] _ in
                await self?.restoreHiddenWindows()
                return .dismiss
            })
        }

        if resultActions.isEmpty {
            return .showResult(
                title: "Ready for \(eventTitle)",
                body: "Minimized \(hiddenCount) distracting windows."
            )
        }
        return .pushActions(resultActions)
    }

    private func buildJoinVideoAction(
        event: CalendarManager.CalendarEvent,
        meta: EventMeta
    ) -> MeetingPrepAction? {
        guard let videoURL = meta.videoURL, let videoType = meta.videoType else {
            return nil
        }
        return MeetingPrepAction(
            id: ActionID(module: "meetingPrep", name: "join.\(meta.stableID)"),
            title: "Join: \(meta.eventTitle)",
            subtitle: "\(videoLabel(for: videoType)) \u{2022} \(meta.timeLabel)",
            iconName: "video.fill",
            relevanceScore: meta.relevance - 0.05,
            keywords: buildKeywords(event: event, extra: ["join", "video", "call"]),
            actionType: .joinVideo,
            meetingTitle: meta.eventTitle,
            startDate: meta.startDate,
            endDate: meta.endDate,
            attendeeNames: meta.attendees,
            videoLinkType: videoType,
            videoURL: videoURL,
            calendarName: meta.calendarTitle,
            calendarColorHex: meta.calendarColorHex
        ) { _ in
            DispatchQueue.main.async { CalendarManager.openVideoLink(videoURL) }
            return .dismiss
        }
    }

    // MARK: - Hide Distractions Action

    private func buildHideDistractionsAction() -> MeetingPrepAction {
        let cfg = config
        return MeetingPrepAction(
            id: ActionID(module: "meetingPrep", name: "hideDistractions"),
            title: "Hide Distractions",
            subtitle: "Minimize windows of distracting apps",
            iconName: "eye.slash",
            relevanceScore: 0.6,
            keywords: [
                "hide", "distractions", "minimize", "focus", "clean",
                "meeting", "prep",
            ],
            actionType: .hideDistractions
        ) { [weak self] _ in
            let count = await self?.hideDistractingWindows(config: cfg) ?? 0
            if count == 0 {
                return .showResult(
                    title: "Already Clean",
                    body: "No distracting windows to hide."
                )
            }
            return .showResult(
                title: "Distractions Hidden",
                body: "Minimized \(count) windows. Use \"Restore Windows\" to bring them back."
            )
        }
    }

    // MARK: - Restore Windows Action

    private func buildRestoreWindowsAction() -> MeetingPrepAction {
        let count = hiddenWindowIDs.count
        return MeetingPrepAction(
            id: ActionID(module: "meetingPrep", name: "restoreWindows"),
            title: "Restore Windows",
            subtitle: "Un-minimize \(count) previously hidden windows",
            iconName: "macwindow.on.rectangle",
            relevanceScore: 0.7,
            keywords: [
                "restore", "windows", "show", "unhide", "bring back",
                "meeting", "done",
            ],
            actionType: .restoreWindows
        ) { [weak self] _ in
            await self?.restoreHiddenWindows()
            return .dismiss
        }
    }

    // MARK: - Window Management

    private func hideDistractingWindows(
        config: MeetingPrepConfig
    ) async -> Int {
        let windows = await MainActor.run {
            windowManager.listWindows(includeMinimized: false)
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        var toHide: [WindowInfo] = []

        for window in windows {
            guard let bundleID = window.bundleID else { continue }
            guard bundleID != ownBundleID else { continue }

            if let keepApps = config.keepApps, !keepApps.isEmpty {
                // If keepApps is set, hide everything NOT in keepApps
                if !keepApps.contains(bundleID) {
                    toHide.append(window)
                }
            } else if let hideApps = config.hideApps, !hideApps.isEmpty {
                // If hideApps is set, only hide those specific apps
                if hideApps.contains(bundleID) {
                    toHide.append(window)
                }
            } else {
                // Default: hide everything except video call apps
                let videoAppBundles: Set<String> = [
                    "us.zoom.xos",
                    "com.google.Chrome",
                    "com.apple.Safari",
                    "com.microsoft.teams",
                    "com.microsoft.teams2",
                ]
                if !videoAppBundles.contains(bundleID) {
                    toHide.append(window)
                }
            }
        }

        var hiddenIDs: [Int] = []
        for window in toHide {
            do {
                try windowManager.minimizeWindow(window)
                hiddenIDs.append(window.id)
            } catch {
                log.warning(
                    "Failed to minimize window \(window.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        hiddenWindowIDs = hiddenIDs
        log.info("Hidden \(hiddenIDs.count, privacy: .public) distracting windows")
        return hiddenIDs.count
    }

    private func restoreHiddenWindows() async {
        let windows = await MainActor.run {
            windowManager.listWindows(includeMinimized: true)
        }

        let idsToRestore = Set(hiddenWindowIDs)
        var restored = 0

        for window in windows where idsToRestore.contains(window.id) {
            guard window.isMinimized else { continue }
            // Un-minimize by resolving AX element and setting minimized = false
            if let axWindow = AXWindowHelper.resolve(
                windowID: window.id, pid: window.pid, frame: window.frame
            ) {
                AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
                restored += 1
            }
        }

        log.info("Restored \(restored, privacy: .public) windows")
        hiddenWindowIDs = []
    }

    // MARK: - Helpers

    private func buildKeywords(
        event: CalendarManager.CalendarEvent,
        extra: [String]
    ) -> [String] {
        var keywords = extra
        keywords.append(
            contentsOf: event.title.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
        )
        keywords.append(event.calendarTitle.lowercased())
        return keywords
    }

    private func videoLabel(for type: VideoLinkType) -> String {
        switch type {
        case .zoom: return "Zoom"
        case .googleMeet: return "Google Meet"
        case .teams: return "Teams"
        }
    }

    private func actionSuffix(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else {
            return raw
        }
        return String(raw[raw.index(after: dotIndex)...])
    }
}

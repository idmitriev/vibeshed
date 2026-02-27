import AppKit
import EventKit
import Foundation
import OSLog

actor CalendarModule: ModuleConfigurable {
    let id = "calendar"
    let displayName = "Calendar"
    let iconName = "calendar"
    var isEnabled = true

    typealias Config = CalendarConfig
    static var defaultConfig: Config? { .init() }

    private var config: CalendarConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("calendar")

    private var cachedEvents: [CalendarManager.CalendarEvent] = []
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 30

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info(
            "Calendar module initialized (lookahead: \(self.config.lookaheadHours, privacy: .public)h)"
        )
    }

    func configDidUpdate(_ config: CalendarConfig) async {
        self.config = config
        cacheTimestamp = .distantPast
        log.debug(
            "Config updated (lookahead: \(config.lookaheadHours, privacy: .public)h)"
        )
    }

    static func validate(
        _ config: CalendarConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.lookaheadHours < 1 || config.lookaheadHours > 168 {
            errors.append(
                "lookaheadHours must be between 1 and 168 (1 week)"
            )
        }
        if config.lookbehindMinutes < 0 || config.lookbehindMinutes > 120 {
            errors.append("lookbehindMinutes must be between 0 and 120")
        }
        if config.excludedCalendars != nil,
           config.includedCalendars != nil
        {
            errors.append(
                "Only one of excludedCalendars or includedCalendars should be set"
            )
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Actions

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        guard CalendarManager.hasAccess else {
            return [buildGrantAccessAction()]
        }
        refreshCacheIfNeeded()
        return buildActions()
    }

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(cacheTimestamp) > cacheTTL else {
            return
        }

        cachedEvents = CalendarManager.fetchEvents(
            lookaheadHours: config.lookaheadHours,
            lookbehindMinutes: config.lookbehindMinutes,
            excludedCalendars: config.excludedCalendars,
            includedCalendars: config.includedCalendars,
            showAllDay: config.showAllDayEvents,
            showDeclined: config.showDeclinedEvents
        )
        cacheTimestamp = now
    }

    private func buildActions() -> [CalendarAction] {
        let enabled = config.enabledActions
        var actions: [CalendarAction] = []

        actions.append(contentsOf: buildEventActions())

        if config.showOpenCalendarAction {
            actions.append(buildOpenCalendarAction())
        }

        if let enabled {
            return actions.filter { action in
                enabled.contains(actionSuffix(action.id))
            }
        }
        return actions
    }

    // MARK: - Event Actions

    private func buildEventActions() -> [CalendarAction] {
        let now = Date()

        return cachedEvents.enumerated().map { index, event in
            let videoLink = CalendarManager.detectVideoLink(
                url: event.url,
                location: event.location,
                notes: event.notes
            )

            let subtitle = formatEventSubtitle(event: event)
            let relevance = computeRelevance(
                event: event, index: index, now: now
            )

            let keywords = buildKeywords(event: event, hasVideo: videoLink != nil)
            let stableInput = "\(event.eventIdentifier)_\(event.startDate.timeIntervalSince1970)"
            let eventID = event.eventIdentifier
            let videoURL = videoLink?.url

            return CalendarAction(
                id: ActionID(
                    module: "calendar",
                    name: "event.\(CalendarManager.stableID(stableInput))"
                ),
                title: event.title,
                subtitle: subtitle,
                iconName: videoLink != nil ? "video.fill" : "calendar",
                relevanceScore: relevance,
                keywords: keywords,
                calendarItemType: .event,
                calendarName: event.calendarTitle,
                calendarColorHex: event.calendarColorHex,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                attendeeNames: event.attendeeNames.isEmpty
                    ? nil : event.attendeeNames,
                videoLinkType: videoLink?.type,
                videoURL: videoURL
            ) { _ in
                DispatchQueue.main.async {
                    if let videoURL {
                        CalendarManager.openVideoLink(videoURL)
                    } else {
                        CalendarManager.openEvent(eventID)
                    }
                }
                return .dismiss
            }
        }
    }

    // MARK: - Open Calendar Action

    private func buildOpenCalendarAction() -> CalendarAction {
        CalendarAction(
            id: ActionID(module: "calendar", name: "openCalendar"),
            title: "Open Calendar",
            subtitle: "Open Calendar.app",
            iconName: "calendar",
            relevanceScore: 0.4,
            keywords: ["calendar", "open", "launch"],
            calendarItemType: .utility
        ) { _ in
            DispatchQueue.main.async {
                CalendarManager.openCalendarApp()
            }
            return .dismiss
        }
    }

    // MARK: - Grant Access Action

    private func buildGrantAccessAction() -> CalendarAction {
        CalendarAction(
            id: ActionID(module: "calendar", name: "grantAccess"),
            title: "Grant Calendar Access",
            subtitle: "Open System Settings to enable calendar access",
            iconName: "lock.open",
            relevanceScore: 0.9,
            keywords: ["calendar", "permission", "access", "grant", "settings"],
            calendarItemType: .utility
        ) { _ in
            let granted = await CalendarManager.requestAccess()
            if granted {
                return .dismiss
            }
            DispatchQueue.main.async {
                CalendarManager.openCalendarPrivacySettings()
            }
            return .showResult(
                title: "Calendar Access Required",
                body: "In System Settings \u{2192} Privacy & Security \u{2192} Calendars, "
                    + "click the \"+\" button, navigate to Vibeshed.app, and add it. "
                    + "Then search for \"calendar\" again."
            )
        }
    }

    // MARK: - Helpers

    private func buildKeywords(
        event: CalendarManager.CalendarEvent,
        hasVideo: Bool
    ) -> [String] {
        var keywords = ["calendar", "event", "meeting"]
        keywords.append(
            contentsOf: event.title.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
        )
        keywords.append(event.calendarTitle.lowercased())
        if hasVideo {
            keywords.append(contentsOf: ["video", "call", "join"])
        }
        return keywords
    }

    private func formatEventSubtitle(
        event: CalendarManager.CalendarEvent
    ) -> String {
        let timeStr: String
        if event.isAllDay {
            timeStr = "All Day"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let start = formatter.string(from: event.startDate)
            let end = formatter.string(from: event.endDate)
            timeStr = "\(start) \u{2013} \(end)"
        }
        return "\(timeStr) \u{2022} \(event.calendarTitle)"
    }

    private func computeRelevance(
        event: CalendarManager.CalendarEvent,
        index: Int,
        now: Date
    ) -> Double {
        let minutesUntil = event.startDate.timeIntervalSince(now) / 60

        if minutesUntil <= 0, now < event.endDate {
            return 0.95
        } else if minutesUntil <= 15 {
            return 0.9
        } else if minutesUntil <= 60 {
            return 0.8
        } else {
            return max(0.4, 0.75 - Double(index) * 0.02)
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

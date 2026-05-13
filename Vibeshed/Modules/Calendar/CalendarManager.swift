import AppKit
import EventKit
import Foundation

enum CalendarManager {

    // MARK: - Permission

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    static func openCalendarPrivacySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Event Store

    private static let store = EKEventStore()

    // MARK: - Data Types

    struct CalendarEvent: Sendable {
        let eventIdentifier: String
        let title: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let calendarTitle: String
        let calendarColorHex: String
        let location: String?
        let url: URL?
        let notes: String?
        let attendeeNames: [String]
        let status: EventStatus
    }

    enum EventStatus: Sendable {
        case confirmed
        case tentative
        case declined
        case none
    }

    // MARK: - Fetch Events

    static func fetchEvents(
        lookaheadHours: Int,
        lookbehindMinutes: Int,
        excludedCalendars: [String]?,
        includedCalendars: [String]?,
        showAllDay: Bool,
        showDeclined: Bool
    ) -> [CalendarEvent] {
        let now = Date()
        let startDate = now.addingTimeInterval(
            -Double(lookbehindMinutes) * 60
        )
        let endDate = now.addingTimeInterval(
            Double(lookaheadHours) * 3600
        )

        let calendars = resolveCalendars(
            excluded: excludedCalendars,
            included: includedCalendars
        )

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )

        let ekEvents = store.events(matching: predicate)

        return ekEvents.compactMap { event in
            if event.isAllDay && !showAllDay { return nil }

            let status = mapStatus(event)
            if status == .declined && !showDeclined { return nil }

            let attendees = (event.attendees ?? [])
                .filter { !$0.isCurrentUser }
                .compactMap { $0.name }

            return CalendarEvent(
                eventIdentifier: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                calendarColorHex: hexColor(from: event.calendar.cgColor),
                location: event.location,
                url: event.url,
                notes: truncateNotes(event.notes),
                attendeeNames: attendees,
                status: status
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Video Link Detection

    static func detectVideoLink(
        url: URL?,
        location: String?,
        notes: String?
    ) -> (type: VideoLinkType, url: URL)? {
        let fields = [
            url?.absoluteString,
            location,
            notes,
        ].compactMap { $0 }

        for field in fields {
            if let match = matchURL(pattern: zoomPattern, in: field) {
                return (.zoom, match)
            }
            if let match = matchURL(pattern: meetPattern, in: field) {
                return (.googleMeet, match)
            }
            if let match = matchURL(pattern: teamsPattern, in: field) {
                return (.teams, match)
            }
        }
        return nil
    }

    // swiftlint:disable force_try
    private static let zoomPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s]*zoom\.us/j/\d+[^\s]*"#
    )
    private static let meetPattern = try! NSRegularExpression(
        pattern: #"https?://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+"#
    )
    private static let teamsPattern = try! NSRegularExpression(
        pattern: #"https?://teams\.microsoft\.com/l/meetup-join/[^\s]+"#
    )
    // swiftlint:enable force_try

    private static func matchURL(
        pattern: NSRegularExpression,
        in text: String
    ) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        return URL(string: String(text[matchRange]))
    }

    // MARK: - Open Helpers

    static func openEvent(_ eventIdentifier: String) {
        let calendarBundleID = "com.apple.iCal"
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: calendarBundleID)
            .first
        {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: calendarBundleID
        ) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: .init()
            )
        }
    }

    static func openVideoLink(_ url: URL) {
        if let zoomURL = rewriteAsZoomAppURL(url) {
            NSWorkspace.shared.open(zoomURL)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Rewrites an https://zoom.us/j/... link to a zoommtg:// URL so it
    /// launches the Zoom app directly instead of routing through the browser.
    private static func rewriteAsZoomAppURL(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host.hasSuffix("zoom.us") else {
            return nil
        }
        guard let parsed = ZoomManager.parseMeetingInput(url.absoluteString) else {
            return nil
        }
        return ZoomManager.joinURL(
            meetingId: parsed.meetingId,
            password: parsed.password
        )
    }

    static func openCalendarApp() {
        let calendarBundleID = "com.apple.iCal"
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: calendarBundleID)
            .first
        {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: calendarBundleID
        ) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: .init()
            )
        }
    }

    // MARK: - Stable ID

    static func stableID(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }

    // MARK: - Private Helpers

    private static func resolveCalendars(
        excluded: [String]?,
        included: [String]?
    ) -> [EKCalendar]? {
        let allCalendars = store.calendars(for: .event)

        if let included, !included.isEmpty {
            let lowered = Set(included.map { $0.lowercased() })
            let filtered = allCalendars.filter {
                lowered.contains($0.title.lowercased())
            }
            return filtered.isEmpty ? nil : filtered
        }

        if let excluded, !excluded.isEmpty {
            let lowered = Set(excluded.map { $0.lowercased() })
            let filtered = allCalendars.filter {
                !lowered.contains($0.title.lowercased())
            }
            return filtered.isEmpty ? nil : filtered
        }

        return nil
    }

    private static func mapStatus(_ event: EKEvent) -> EventStatus {
        guard let attendees = event.attendees else { return .none }
        guard let me = attendees.first(where: { $0.isCurrentUser }) else {
            return .none
        }
        switch me.participantStatus {
        case .accepted: return .confirmed
        case .tentative: return .tentative
        case .declined: return .declined
        default: return .none
        }
    }

    private static func hexColor(from cgColor: CGColor) -> String {
        guard let rgb = cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ),
            let components = rgb.components,
            components.count >= 3
        else {
            return "#808080"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func truncateNotes(_ notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        if notes.count > 2000 {
            return String(notes.prefix(2000))
        }
        return notes
    }
}

import EventKit
import ShowreelCore

/// Sample events for calendar scenes, in a local "Showreel" calendar that is
/// emptied first, so every take shows the same agenda relative to its time.
@MainActor
enum CalendarFixtures {
    static let calendarName = "Showreel"

    static func replace(with events: [EventSetup]) async throws {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw AgentError("no Calendar access for ShowreelAgent — run `scripts/showreel vm grant`")
        }
        let calendar = try showreelCalendar(in: store)
        let now = Date()
        let window = store.predicateForEvents(
            withStart: now.addingTimeInterval(-7 * 86400), end: now.addingTimeInterval(7 * 86400),
            calendars: [calendar]
        )
        for old in store.events(matching: window) {
            try store.remove(old, span: .thisEvent, commit: false)
        }
        for setup in events {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = setup.title
            event.startDate = now.addingTimeInterval(setup.startsIn * 60)
            event.endDate = event.startDate.addingTimeInterval(setup.minutes * 60)
            event.url = setup.url.flatMap(URL.init(string:))
            event.location = setup.location
            event.notes = setup.notes
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        Log.info("calendar: \(events.count) event(s) in “\(calendarName)”")
    }

    private static func showreelCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarName }) {
            return existing
        }
        guard let source = store.sources.first(where: { $0.sourceType == .local })
            ?? store.defaultCalendarForNewEvents?.source
        else { throw AgentError("no local calendar source to add “\(calendarName)” to") }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName
        calendar.source = source
        calendar.cgColor = CGColor(srgbRed: 0.83, green: 0.14, blue: 0.36, alpha: 1)   // Vibeshed's raspberry
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}

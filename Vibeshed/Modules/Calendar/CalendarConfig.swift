import Foundation

struct CalendarConfig: Codable, Sendable, Equatable {
    var lookaheadHours: Int = 24
    var lookbehindMinutes: Int = 30
    var excludedCalendars: [String]?
    var includedCalendars: [String]?
    var showAllDayEvents: Bool = false
    var showDeclinedEvents: Bool = false
    var showOpenCalendarAction: Bool = true
    var enabledActions: Set<String>?
}

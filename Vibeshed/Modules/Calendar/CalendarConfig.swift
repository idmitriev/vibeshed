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

extension CalendarConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        lookaheadHours = try container.decodeIfPresent(Int.self, forKey: .lookaheadHours) ?? defaults.lookaheadHours
        lookbehindMinutes = try container.decodeIfPresent(Int.self, forKey: .lookbehindMinutes)
            ?? defaults.lookbehindMinutes
        excludedCalendars = try container.decodeIfPresent([String].self, forKey: .excludedCalendars)
        includedCalendars = try container.decodeIfPresent([String].self, forKey: .includedCalendars)
        showAllDayEvents = try container.decodeIfPresent(Bool.self, forKey: .showAllDayEvents)
            ?? defaults.showAllDayEvents
        showDeclinedEvents = try container.decodeIfPresent(Bool.self, forKey: .showDeclinedEvents)
            ?? defaults.showDeclinedEvents
        showOpenCalendarAction = try container.decodeIfPresent(Bool.self, forKey: .showOpenCalendarAction)
            ?? defaults.showOpenCalendarAction
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}

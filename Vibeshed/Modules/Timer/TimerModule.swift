import AppKit
import Foundation
import OSLog

actor TimerModule: ModuleConfigurable {
    let id = "timer"
    let displayName = "Timers"
    let iconName = "timer"
    var isEnabled = true

    typealias Config = TimerConfig
    static var defaultConfig: Config? { .init() }

    private var config: TimerConfig = .init()
    private var context: ModuleContext?
    private var store: TimerStore?
    private var scheduler: TimerScheduler?
    private let log = Log.module("timer")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        let eventBus = context.eventBus
        let timerStore = await MainActor.run { TimerStore() }
        self.store = timerStore
        let timerScheduler = await MainActor.run {
            TimerScheduler(store: timerStore, eventBus: eventBus)
        }
        self.scheduler = timerScheduler
        let maxActive = self.config.maxActiveTimers
        await MainActor.run {
            timerStore.updateConfig(maxActive: maxActive)
            timerScheduler.start()
        }
        log.info("Timer module initialized")
    }

    func teardown() async {
        let currentScheduler = scheduler
        await MainActor.run { currentScheduler?.stop() }
        log.info("Timer module torn down")
    }

    func configDidUpdate(_ config: TimerConfig) async {
        self.config = config
        let maxActive = config.maxActiveTimers
        let currentStore = store
        await MainActor.run {
            currentStore?.updateConfig(maxActive: maxActive)
        }
        log.debug("Config updated")
    }

    static func validate(
        _ config: TimerConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxActiveTimers < 1
            || config.maxActiveTimers > 100
        {
            errors.append(
                "maxActiveTimers must be between 1 and 100"
            )
        }
        if config.presetDurations.isEmpty {
            errors.append("presetDurations must not be empty")
        }
        for dur in config.presetDurations
        where dur < 1 || dur > 1440 {
            errors.append(
                "presetDurations values must be between 1 and 1440 minutes"
            )
            break
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Actions

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        let currentStore = store
        let items = await MainActor.run {
            currentStore?.items ?? []
        }
        var actions: [any Action] = []

        actions.append(
            contentsOf: buildActiveActions(items: items)
        )
        actions.append(buildSetTimerAction())
        actions.append(contentsOf: buildPresetActions())
        actions.append(buildSetReminderAction())

        let activeCount = items.filter {
            $0.status == .active
        }.count
        if activeCount > 0 {
            actions.append(buildCancelAllAction())
        }

        let completedCount = items.filter {
            $0.status != .active
        }.count
        if completedCount > 0 {
            actions.append(buildClearCompletedAction())
        }

        if let enabled = config.enabledActions {
            actions = actions.filter { action in
                let raw = action.id.rawValue
                guard let dotIndex = raw.firstIndex(of: ".") else {
                    return true
                }
                let name = String(
                    raw[raw.index(after: dotIndex)...]
                )
                return enabled.contains(name)
            }
        }

        return actions
    }

    // MARK: - Active Timer Actions

    private func buildActiveActions(
        items: [TimerEntry]
    ) -> [TimerAction] {
        let now = Date()
        return items.compactMap { entry in
            guard entry.status == .active else { return nil }

            let remaining = entry.fireDate.timeIntervalSince(now)
            let subtitle = remaining > 0
                ? "\(TimerParser.formatCountdown(remaining)) remaining"
                : "Firing..."

            let entryID = entry.id
            let currentStore = store
            let currentScheduler = scheduler
            let eventBus = context?.eventBus

            return TimerAction(
                id: ActionID(
                    module: "timer",
                    name: "active.\(entry.id)"
                ),
                title: entry.label.isEmpty
                    ? (entry.type == .timer ? "Timer" : "Reminder")
                    : entry.label,
                subtitle: subtitle,
                iconName: entry.type == .timer
                    ? "timer" : "bell",
                relevanceScore: 0.95,
                keywords: [
                    "timer", "reminder", "active", "running",
                    "cancel",
                ] + entry.label.lowercased()
                    .components(
                        separatedBy: .whitespacesAndNewlines
                    )
                    .filter { !$0.isEmpty },
                timerItemType: entry.type == .timer
                    ? .timer : .reminder,
                fireDate: entry.fireDate,
                createdDate: entry.createdDate,
                originalDuration: entry.duration,
                label: entry.label,
                isActive: true
            ) { _ in
                await MainActor.run {
                    currentStore?.cancel(id: entryID)
                    currentScheduler?.cancelNotification(
                        id: entryID
                    )
                }
                Task {
                    await eventBus?.publish(
                        .moduleActionsChanged(moduleID: "timer")
                    )
                }
                return .showResult(
                    title: "Timer Cancelled",
                    body: "The timer has been cancelled."
                )
            }
        }
    }

    // MARK: - Set Timer Action

    private func buildSetTimerAction() -> TimerAction {
        let currentStore = store
        let currentScheduler = scheduler
        let eventBus = context?.eventBus
        let defaultSound = config.defaultSound

        return TimerAction(
            id: ActionID(module: "timer", name: "setTimer"),
            title: "Set Timer",
            subtitle: "Set a countdown timer",
            iconName: "timer",
            relevanceScore: 0.7,
            keywords: [
                "timer", "set", "start", "countdown", "alarm",
            ],
            parameters: [
                ActionParameter(
                    id: "duration",
                    label: "Duration",
                    type: .text(
                        placeholder: "e.g. 5m, 1h30m, 90s, 1:30"
                    ),
                    isRequired: true
                ),
                ActionParameter(
                    id: "label",
                    label: "Label",
                    type: .text(placeholder: "Optional label"),
                    isRequired: false
                ),
            ],
            timerItemType: .utility
        ) { values in
            guard let durationStr = values["duration"] as? String,
                  let seconds = TimerParser.parseDuration(durationStr)
            else {
                return .showResult(
                    title: "Invalid Duration",
                    body: "Use formats like: 5m, 1h30m, 90s, 1:30, or just a number for minutes"
                )
            }

            let label = (values["label"] as? String) ?? ""

            await MainActor.run {
                currentScheduler?.ensureNotificationPermission()
                currentStore?.addTimer(
                    duration: seconds,
                    label: label,
                    sound: defaultSound
                )
            }
            Task {
                await eventBus?.publish(
                    .moduleActionsChanged(moduleID: "timer")
                )
            }

            let formatted = TimerParser.formatDurationLong(seconds)
            return .showResult(
                title: "Timer Set",
                body: label.isEmpty
                    ? "Timer set for \(formatted)"
                    : "\"\(label)\" set for \(formatted)"
            )
        }
    }

    // MARK: - Preset Duration Actions

    private func buildPresetActions() -> [TimerAction] {
        let currentStore = store
        let currentScheduler = scheduler
        let eventBus = context?.eventBus
        let defaultSound = config.defaultSound

        return config.presetDurations.map { minutes in
            let duration = TimeInterval(minutes * 60)
            let label = TimerParser.formatDurationLong(duration)

            return TimerAction(
                id: ActionID(
                    module: "timer",
                    name: "preset.\(minutes)"
                ),
                title: "Timer \(label)",
                subtitle: "Start a \(label) timer",
                iconName: "timer",
                relevanceScore: 0.6,
                keywords: [
                    "timer", "preset", "\(minutes)", "minute",
                    "start",
                ],
                timerItemType: .utility
            ) { _ in
                await MainActor.run {
                    currentScheduler?.ensureNotificationPermission()
                    currentStore?.addTimer(
                        duration: duration,
                        label: "\(label) timer",
                        sound: defaultSound
                    )
                }
                Task {
                    await eventBus?.publish(
                        .moduleActionsChanged(moduleID: "timer")
                    )
                }
                return .showResult(
                    title: "Timer Set",
                    body: "Timer set for \(label)"
                )
            }
        }
    }

    // MARK: - Set Reminder Action

    private func buildSetReminderAction() -> TimerAction {
        let currentStore = store
        let currentScheduler = scheduler
        let eventBus = context?.eventBus
        let defaultSound = config.defaultSound

        return TimerAction(
            id: ActionID(module: "timer", name: "setReminder"),
            title: "Set Reminder",
            subtitle: "Set a reminder for a specific time",
            iconName: "bell",
            relevanceScore: 0.65,
            keywords: [
                "reminder", "set", "alarm", "notify", "schedule",
            ],
            parameters: [
                ActionParameter(
                    id: "time",
                    label: "Time",
                    type: .text(
                        placeholder: "e.g. 3:00 PM, 15:00, in 2 hours"
                    ),
                    isRequired: true
                ),
                ActionParameter(
                    id: "label",
                    label: "Label",
                    type: .text(placeholder: "Optional label"),
                    isRequired: false
                ),
            ],
            timerItemType: .utility
        ) { values in
            guard let timeStr = values["time"] as? String,
                  let fireDate = TimerParser.parseTime(timeStr)
            else {
                return .showResult(
                    title: "Invalid Time",
                    body: "Use formats like: 3:00 PM, 15:00, 3pm, or \"in 2 hours\""
                )
            }

            let label = (values["label"] as? String) ?? ""

            await MainActor.run {
                currentScheduler?.ensureNotificationPermission()
                currentStore?.addReminder(
                    fireDate: fireDate,
                    label: label,
                    sound: defaultSound
                )
            }
            Task {
                await eventBus?.publish(
                    .moduleActionsChanged(moduleID: "timer")
                )
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let timeFormatted = formatter.string(from: fireDate)

            return .showResult(
                title: "Reminder Set",
                body: label.isEmpty
                    ? "Reminder set for \(timeFormatted)"
                    : "\"\(label)\" set for \(timeFormatted)"
            )
        }
    }

    // MARK: - Cancel All Action

    private func buildCancelAllAction() -> TimerAction {
        let currentStore = store
        let currentScheduler = scheduler
        let eventBus = context?.eventBus

        return TimerAction(
            id: ActionID(module: "timer", name: "cancelAll"),
            title: "Cancel All Timers",
            subtitle: "Cancel all active timers and reminders",
            iconName: "xmark.circle",
            relevanceScore: 0.4,
            keywords: [
                "cancel", "all", "timer", "reminder", "stop",
                "clear",
            ],
            timerItemType: .utility
        ) { _ in
            let activeIDs = await MainActor.run {
                let ids =
                    currentStore?.activeItems.map(\.id) ?? []
                currentStore?.cancelAll()
                return ids
            }
            for entryID in activeIDs {
                await MainActor.run {
                    currentScheduler?.cancelNotification(
                        id: entryID
                    )
                }
            }
            Task {
                await eventBus?.publish(
                    .moduleActionsChanged(moduleID: "timer")
                )
            }
            return .showResult(
                title: "All Cancelled",
                body: "All active timers and reminders have been cancelled."
            )
        }
    }

    // MARK: - Clear Completed Action

    private func buildClearCompletedAction() -> TimerAction {
        let currentStore = store
        let eventBus = context?.eventBus

        return TimerAction(
            id: ActionID(
                module: "timer",
                name: "clearCompleted"
            ),
            title: "Clear Completed",
            subtitle: "Remove fired and cancelled timers",
            iconName: "trash",
            relevanceScore: 0.3,
            keywords: [
                "clear", "completed", "remove", "fired",
                "cancelled", "clean",
            ],
            timerItemType: .utility
        ) { _ in
            await MainActor.run {
                currentStore?.removeCompleted()
            }
            Task {
                await eventBus?.publish(
                    .moduleActionsChanged(moduleID: "timer")
                )
            }
            return .showResult(
                title: "Cleared",
                body: "Completed timers have been removed."
            )
        }
    }
}

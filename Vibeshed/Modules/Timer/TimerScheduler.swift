import AppKit
import Foundation
import OSLog
import UserNotifications

@MainActor
final class TimerScheduler {
    private let store: TimerStore
    private let eventBus: EventBus?
    private let log = Log.module("timer")
    private var tickTimer: DispatchSourceTimer?
    private var notificationPermissionRequested = false

    init(store: TimerStore, eventBus: EventBus?) {
        self.store = store
        self.eventBus = eventBus
    }

    func start() {
        guard tickTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.resume()
        tickTimer = timer
        log.info("Timer scheduler started")
    }

    func stop() {
        tickTimer?.cancel()
        tickTimer = nil
        log.info("Timer scheduler stopped")
    }

    func cancelNotification(id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
    }

    func ensureNotificationPermission() {
        guard !notificationPermissionRequested else { return }
        notificationPermissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                Log.module("timer").error(
                    "Notification permission error: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                Log.module("timer").info(
                    "Notification permission granted: \(granted, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        let active = store.activeItems

        for entry in active where entry.fireDate <= now {
            fire(entry: entry)
        }
    }

    private func fire(entry: TimerEntry) {
        store.markFired(id: entry.id)
        postNotification(entry: entry)
        playSound(named: entry.sound)

        log.info("Timer fired: \(entry.label, privacy: .public)")

        let bus = eventBus
        Task {
            await bus?.publish(.moduleActionsChanged(moduleID: "timer"))
        }
    }

    // MARK: - Notification

    private func postNotification(entry: TimerEntry) {
        let content = UNMutableNotificationContent()

        switch entry.type {
        case .timer:
            content.title = "Timer Complete"
            if entry.label.isEmpty {
                content.body = TimerParser.formatDurationLong(entry.duration ?? 0) + " timer finished"
            } else {
                content.body = entry.label
            }
        case .reminder:
            content.title = "Reminder"
            content.body = entry.label.isEmpty ? "Time's up!" : entry.label
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: entry.id,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.module("timer").error(
                    "Failed to post notification: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func playSound(named name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

}

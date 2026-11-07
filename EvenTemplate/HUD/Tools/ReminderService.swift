// ReminderService.swift
//
// In-app reminders (no Apple Reminders). Saved in Documents/reminders.json.
// While the app runs, a timer checks for due reminders and calls `onDue`
// (the HUD shows them on the lens). As a safety net each reminder also
// schedules a local notification, so it still alerts if iOS stops the app.
//
// Public API:
//   ReminderService()
//   @Published reminders: [Reminder]       // upcoming, soonest first
//   onDue: ((Reminder) -> Void)?
//   add(text:at:) / delete(id:) / deleteAll()
//   start() / stop()                        // the due-check timer

import Foundation
import UserNotifications

struct Reminder: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let dueAt: Date
}

@MainActor
final class ReminderService: ObservableObject {

    // MARK: - State

    @Published private(set) var reminders: [Reminder] = []
    var onDue: ((Reminder) -> Void)?

    private let file = JsonFileStore<[Reminder]>(fileName: "reminders.json")
    private var timerTask: Task<Void, Never>?

    init() {
        reminders = (file.load() ?? []).sorted { $0.dueAt < $1.dueAt }
    }

    // MARK: - Editing

    func add(text: String, at date: Date) {
        let reminder = Reminder(id: UUID(), text: text, dueAt: date)
        reminders.append(reminder)
        reminders.sort { $0.dueAt < $1.dueAt }
        file.save(reminders)
        scheduleNotification(for: reminder)
    }

    func delete(id: UUID) {
        reminders.removeAll { $0.id == id }
        file.save(reminders)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func deleteAll() {
        let ids = reminders.map(\.id.uuidString)
        reminders = []
        file.save(reminders)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Due checking

    func start() {
        guard timerTask == nil else { return }
        checkDue()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(HudConstants.reminderCheckIntervalSeconds * 1_000_000_000))
                self?.checkDue()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func checkDue() {
        let now = Date()
        let due = reminders.filter { $0.dueAt <= now }
        guard !due.isEmpty else { return }
        reminders.removeAll { $0.dueAt <= now }
        file.save(reminders)
        due.forEach { onDue?($0) }
    }

    // MARK: - Notifications (backup)

    private func scheduleNotification(for reminder: Reminder) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "G2HUD"
            content.body = reminder.text
            content.sound = .default
            let seconds = max(1, reminder.dueAt.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger))
        }
    }
}

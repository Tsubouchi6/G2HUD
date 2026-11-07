// RemindTab.swift
//
// Lens tab: upcoming reminders, soonest first, with a countdown on the next one.
//
// Public API: RemindTab(service:)  — LensTab with id "remind".

import Combine
import Foundation

@MainActor
final class RemindTab: LensTab {

    let id = "remind"
    let title = "リマインダー"
    let voiceNames = ["リマインダー", "リマインド", "予定", "remind", "reminders", "reminder"]
    var onChange: (() -> Void)?

    private let service: ReminderService
    private var subscription: AnyCancellable?

    init(service: ReminderService) {
        self.service = service
        subscription = service.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onChange?() }
    }

    func page() -> LensPage {
        guard !service.reminders.isEmpty else {
            return LensPage(lines: ["(say: メガネ 5時にロット確認)"], anchor: .top)
        }
        let now = Date()
        let lines = service.reminders.enumerated().map { index, reminder in
            let time = Self.timeText(reminder.dueAt, now: now)
            let countdown = index == 0 ? "  (\(Self.countdownText(reminder.dueAt, now: now)))" : ""
            return "\(time) \(reminder.text)\(countdown)"
        }
        return LensPage(lines: lines, anchor: .top)
    }

    // MARK: - Formatting

    private static func timeText(_ date: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }

    private static func countdownText(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return minutes < 60 ? "あと\(minutes)分" : "あと\(minutes / 60)時間\(minutes % 60)分"
    }
}

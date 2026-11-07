// ListeningScheduler.swift
//
// Starts and stops a Listen recording at clock times the user asked for
// ("listen from 5:08 to 5:09", "write it down for 10 minutes"). One plan at a
// time: a new plan, a manual stop, or turning the HUD off replaces it.
// Times are the phone's local clock.
//
// Public API:
//   ListeningScheduler()
//   plan(start:stop:begin:end:) -> Bool     // nil start = now (begin runs right away); nil stop = until told
//   cancel() -> Bool                        // true if a start or stop was still waiting
//   static times(start:stop:minutes:) -> (start: Date?, stop: Date?)   // from "HH:mm" text / a duration
//   static clock(_ date:) -> String         // "05:08"

import Foundation

@MainActor
final class ListeningScheduler {

    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    // MARK: - Planning

    /// Runs `begin` at `start` (now if nil or past) and `end` at `stop`.
    /// Returns begin's result when it ran right away, true when it's waiting.
    func plan(start: Date?, stop: Date?, begin: @escaping @MainActor () -> Bool, end: @escaping @MainActor () -> Void) -> Bool {
        _ = cancel()
        if let stop { stopTask = Self.run(at: stop, end) }
        guard let start, start > .now else {
            let started = begin()
            if !started { _ = cancel() }
            return started
        }
        startTask = Self.run(at: start) { _ = begin() }
        return true
    }

    func cancel() -> Bool {
        let waiting = startTask != nil || stopTask != nil
        startTask?.cancel()
        stopTask?.cancel()
        startTask = nil
        stopTask = nil
        return waiting
    }

    private static func run(at date: Date, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            let wait = date.timeIntervalSinceNow
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }  // cancelled
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    // MARK: - Times

    /// "05:08" / "" and "05:09" / "" (or a duration in minutes) -> dates.
    /// A start already past this minute means now; the stop is the next time
    /// the clock shows it after the start.
    nonisolated static func times(start: String, stop: String, minutes: Int) -> (start: Date?, stop: Date?) {
        let now = Date.now
        let startDate = next(clock: start, after: now.addingTimeInterval(-60))
        let from = startDate ?? now
        let stopDate = next(clock: stop, after: from) ?? (minutes > 0 ? from.addingTimeInterval(Double(minutes) * 60) : nil)
        return (startDate.flatMap { $0 > now ? $0 : nil }, stopDate)
    }

    /// Next moment after `date` when the local clock shows "H:mm".
    nonisolated private static func next(clock text: String, after date: Date) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return Calendar.current.nextDate(
            after: date, matching: DateComponents(hour: parts[0], minute: parts[1], second: 0),
            matchingPolicy: .nextTime
        )
    }

    nonisolated static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

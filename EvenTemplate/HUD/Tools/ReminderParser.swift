// ReminderParser.swift
//
// Turns a spoken reminder into (time, text). Handles common Japanese and
// English forms; times use the phone's current time zone.
//   "5時にロット確認"            "17時30分に電話"       "3時半に休憩"
//   "30分後に検査"              "2時間後に報告"        "明日8時に安全靴"
//   "remind me at 5 to call"     "in 10 minutes check the oven"
// The speech engine writes numbers as digits ("20名"), so only digits are parsed.
//
// Public API:
//   ReminderParser.parse(_ input: String, now: Date = Date()) -> (date: Date, text: String)?

import Foundation

enum ReminderParser {

    // MARK: - Public

    static func parse(_ input: String, now: Date = Date()) -> (date: Date, text: String)? {
        let text = input.lowercased()
        if let relative = parseRelative(text, now: now) { return relative }
        if let clock = parseClock(text, now: now) { return clock }
        return nil
    }

    // MARK: - Relative ("30分後", "in 10 minutes")

    private static func parseRelative(_ text: String, now: Date) -> (date: Date, text: String)? {
        let patterns: [(String, Double)] = [
            (#"(\d+)\s*分後"#, 60), (#"(\d+)\s*時間後"#, 3600), (#"(\d+)\s*秒後"#, 1),
            (#"in\s+(\d+)\s*(?:minutes|minute|mins|min)"#, 60),
            (#"in\s+(\d+)\s*(?:hours|hour|hrs|hr)"#, 3600),
        ]
        for (pattern, secondsPerUnit) in patterns {
            guard let match = firstMatch(pattern, in: text), let amount = Double(match.groups[0]) else { continue }
            let date = now.addingTimeInterval(amount * secondsPerUnit)
            return (date, cleanText(text, removing: match.range))
        }
        return nil
    }

    // MARK: - Clock time ("5時", "17:30", "at 5 pm")

    private static func parseClock(_ text: String, now: Date) -> (date: Date, text: String)? {
        let patterns = [
            #"(\d{1,2})\s*時\s*(半|(\d{1,2})\s*分)?"#,
            #"(\d{1,2}):(\d{2})"#,
            #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#,
        ]
        for pattern in patterns {
            guard let match = firstMatch(pattern, in: text), let rawHour = Int(match.groups[0]) else { continue }
            var hour = rawHour
            var minute = 0
            if match.groups.count > 1 {
                let second = match.groups[1]
                if second == "半" { minute = 30 } else if let value = Int(second) { minute = value }
            }
            if match.groups.count > 2, let value = Int(match.groups[2]) { minute = value }

            let isPm = text.contains("午後") || text.contains("夕方") || text.contains("夜") || match.groups.last == "pm"
            let isAm = text.contains("午前") || text.contains("朝") || match.groups.last == "am"
            if isPm, hour < 12 { hour += 12 }
            if isAm, hour == 12 { hour = 0 }
            guard hour < 24, minute < 60 else { continue }

            let tomorrow = text.contains("明日") || text.contains("あした") || text.contains("tomorrow")
            let date = nextOccurrence(hour: hour, minute: minute, tomorrow: tomorrow,
                                      ampmGiven: isPm || isAm, now: now)
            return (date, cleanText(text, removing: match.range))
        }
        return nil
    }

    /// Today at hour:minute, or the next sensible time after `now`.
    /// Without am/pm, "5時" at 13:00 means 17:00 (the next 5 o'clock).
    private static func nextOccurrence(hour: Int, minute: Int, tomorrow: Bool, ampmGiven: Bool, now: Date) -> Date {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        if tomorrow { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }

        func at(_ h: Int) -> Date {
            calendar.date(bySettingHour: h, minute: minute, second: 0, of: day) ?? now
        }
        var candidate = at(hour)
        if !tomorrow, candidate <= now {
            if !ampmGiven, hour < 12, at(hour + 12) > now {
                candidate = at(hour + 12)
            } else {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
        }
        return candidate
    }

    // MARK: - Text cleanup

    /// Words that mean "remind me" rather than being the reminder itself.
    private static let fillerWords = [
        "リマインドして", "リマインド", "思い出させて", "教えて", "知らせて", "通知して",
        "明日", "あした", "午後", "午前", "夕方", "朝", "夜",
        "remind me", "reminder", "tomorrow", "to ", "that ",
    ]

    private static func cleanText(_ text: String, removing range: NSRange) -> String {
        var result = (text as NSString).replacingCharacters(in: range, with: " ")
        for word in fillerWords {
            result = result.replacingOccurrences(of: word, with: " ")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " 、。,.!！?？にをでのはがと"))
        return result.isEmpty ? "Reminder" : result
    }

    // MARK: - Regex helper

    private struct Match {
        let range: NSRange
        /// Capture groups in order; "" for groups that didn't take part.
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        let groups = (1 ..< result.numberOfRanges).map { index -> String in
            let range = result.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }
        return Match(range: result.range, groups: groups)
    }
}

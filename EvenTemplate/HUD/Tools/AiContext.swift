// AiContext.swift
//
// The context line sent with every AI question (on-device AI and Claude on
// the PC), so answers use the real now and the right language:
//   "[Context: Saturday 2026-11-07 15:18, time zone Asia/Tokyo. Reply in Portuguese.]"
//
// Public API: AiContext.line(language:) -> String

import Foundation

enum AiContext {

    static func line(language: HudLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        let now = formatter.string(from: Date())
        return "[Context: \(now), time zone \(TimeZone.current.identifier). Reply in \(language.englishName).]"
    }
}

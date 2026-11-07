// AiChatArchive.swift
//
// Saved AI chats (questions and answers), one plain-text file each in
// Documents/AIChats, visible in the Files app ("On My iPhone > G2HUD > AIChats"):
//
//   2026-11-07 15:20 · 日本語 · Tomato prices
//   > トマトの値段は？
//   1kgで約800円です。
//
// Saving is asked for by voice in any wording ("save this", "この会話保存して"):
// the AI (iPhone or Claude) recognizes it and calls saveCurrent(title:language:).
//
// Public API:
//   AiChatArchive()
//   @Published chats: [URL]                       // newest first
//   currentTranscript: (() -> [String])?          // set by AiTab: the chat on screen
//   saveCurrent(title:language:) -> Bool          // false when the chat is empty
//   read(_ url:) -> String / delete(_ url:) / refreshList()
//   static title(for url:) -> String              // "2026-11-07 15:20 Tomato prices"

import Foundation

@MainActor
final class AiChatArchive: ObservableObject {

    // MARK: - State

    @Published private(set) var chats: [URL] = []

    var currentTranscript: (() -> [String])?

    init() {
        refreshList()
    }

    // MARK: - Writing

    func saveCurrent(title: String, language: HudLanguage) -> Bool {
        let lines = currentTranscript?() ?? []
        guard !lines.isEmpty, let folder = try? Self.folder() else { return false }
        let now = Date()
        let cleanTitle = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let header = "\(Self.format(now, "yyyy-MM-dd HH:mm")) · \(language.displayName) · \(cleanTitle)"
        let url = folder.appendingPathComponent("aichat-\(Self.format(now, "yyyy-MM-dd_HH-mm-ss")).txt")
        let text = ([header] + lines).joined(separator: "\n") + "\n"
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return false }
        refreshList()
        return true
    }

    // MARK: - Reading

    func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshList()
    }

    func refreshList() {
        guard let folder = try? Self.folder(),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        chats = urls
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Header "2026-11-07 15:20 · 日本語 · Tomato prices" -> "2026-11-07 15:20 Tomato prices".
    static func title(for url: URL) -> String {
        let header = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n").first ?? ""
        let parts = header.components(separatedBy: " · ")
        guard parts.count >= 3 else { return url.deletingPathExtension().lastPathComponent }
        return "\(parts[0]) \(parts[2...].joined(separator: " · "))"
    }

    // MARK: - Helpers

    private static func folder() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = documents.appendingPathComponent(HudConstants.aiChatsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

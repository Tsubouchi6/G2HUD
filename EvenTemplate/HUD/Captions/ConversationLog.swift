// ConversationLog.swift
//
// Saves what was said while the HUD runs, so it can be reviewed (and studied)
// later. One plain-text file per HUD session in Documents/Conversations,
// visible in the Files app ("On My iPhone > G2HUD > Conversations"):
//
//   2026-11-07 14:32 · 日本語
//   14:32:05  次のロット何時から？
//   14:32:09  3時からです
//
// Each line is written immediately, so nothing is lost if the app is closed.
//
// ListeningLog (below) is the same thing for "listen to this" clips: started
// when the user asks the AI to pay attention, kept in Documents/Listening, with
// a title in the header ("2026-11-07 15:40 · 日本語 · Store").
//
// Public API:
//   ConversationLog()   /   ListeningLog()
//   @Published sessions: [URL]                 // newest first
//   isRecording: Bool
//   startSession(language:title:) / endSession()
//   append(_ phrase: String)                   // no-op when no session is open
//   read(_ url: URL) -> String
//   delete(_ url: URL) / refreshList()
//   static title(for url: URL) -> String       // "2026-11-07 14:32" or "2026-11-07 15:40 Store"

import Foundation

@MainActor
class ConversationLog: ObservableObject {

    // MARK: - State

    @Published private(set) var sessions: [URL] = []

    private var currentFile: URL?
    private let folderName: String
    private let filePrefix: String

    init(folderName: String = HudConstants.conversationsFolderName, filePrefix: String = "conv-") {
        self.folderName = folderName
        self.filePrefix = filePrefix
        refreshList()
    }

    var isRecording: Bool { currentFile != nil }

    // MARK: - Writing

    func startSession(language: HudLanguage, title: String? = nil) {
        guard currentFile == nil, let folder = try? folderURL() else { return }
        let now = Date()
        let url = folder.appendingPathComponent("\(filePrefix)\(Self.format(now, "yyyy-MM-dd_HH-mm-ss")).txt")
        let titlePart = title.map { " · " + $0.replacingOccurrences(of: "\n", with: " ") } ?? ""
        let header = "\(Self.format(now, "yyyy-MM-dd HH:mm")) · \(language.displayName)\(titlePart)\n"
        guard FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8)) else { return }
        currentFile = url
        refreshList()
    }

    func endSession() {
        guard let url = currentFile else { return }
        currentFile = nil
        // Drop sessions where nothing was said (header line only).
        if read(url).split(separator: "\n").count <= 1 {
            try? FileManager.default.removeItem(at: url)
        }
        refreshList()
    }

    func append(_ phrase: String) {
        guard let url = currentFile, let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        let line = "\(Self.format(Date(), "HH:mm:ss"))  \(phrase)\n"
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    // MARK: - Reading

    func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func delete(_ url: URL) {
        guard url != currentFile else { return }  // don't delete the session being written
        try? FileManager.default.removeItem(at: url)
        refreshList()
    }

    func refreshList() {
        guard let folder = try? folderURL(),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        sessions = urls
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Header "2026-11-07 14:32 · 日本語[ · Store]" -> "2026-11-07 14:32[ Store]".
    static func title(for url: URL) -> String {
        let header = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n").first ?? ""
        let parts = header.components(separatedBy: " · ")
        guard let date = parts.first, !date.isEmpty else { return url.deletingPathExtension().lastPathComponent }
        return ([date] + parts.dropFirst(2)).joined(separator: " ")
    }

    // MARK: - Helpers

    private func folderURL() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
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

/// "Listen to this" clips (its own type so screens can get it from the environment).
@MainActor
final class ListeningLog: ConversationLog {
    init() {
        super.init(folderName: HudConstants.listeningFolderName, filePrefix: "listen-")
    }
}

// SavedTab.swift
//
// Lens tab: saved AI chats and saved real conversations, newest first, all
// controlled by voice (with the wake word, while this tab is open):
//   "2番" / "number 2" / "número 2"   -> open item 2
//   "翻訳して" / "translate" / "traduz" -> show each line with its translation
//     (add a language to choose it: "英語に翻訳", "translate to Portuguese")
//   "一覧" / "list" / "lista"          -> back to the list
// Scrolling uses the normal up/down commands.
//
// Public API:
//   SavedTab(conversations:chats:translator:)  — LensTab with id "saved"
//   open(number:) -> Bool                      // 1-based, as shown in the list
//   translate(to:)                             // nil = default target language
//   showList()
//   isShowingItem: Bool

import Combine
import Foundation

@MainActor
final class SavedTab: LensTab {

    let id = "saved"
    var title: String { HudText.t(.tabSaved) }
    let voiceNames = ["履歴", "りれき", "保存一覧", "保存済み", "saved", "history", "salvos", "histórico", "historico"]
    var onChange: (() -> Void)?

    // MARK: - State

    private enum Kind { case aiChat, conversation }
    private struct Item {
        let url: URL
        let kind: Kind
        let title: String
    }
    private struct OpenItem {
        let item: Item
        let language: HudLanguage
        let lines: [String]
        var translations: [String]?
        var translating = false
        var translationFailed = false
    }

    private let conversations: ConversationLog
    private let chats: AiChatArchive
    private let translator: Translator
    private var items: [Item] = []
    private var opened: OpenItem?
    private var subscriptions: [AnyCancellable] = []

    init(conversations: ConversationLog, chats: AiChatArchive, translator: Translator) {
        self.conversations = conversations
        self.chats = chats
        self.translator = translator
        for publisher in [conversations.objectWillChange, chats.objectWillChange] {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reloadItems() }
                .store(in: &subscriptions)
        }
        reloadItems()
    }

    var isShowingItem: Bool { opened != nil }

    // MARK: - Page

    func page() -> LensPage {
        if let opened { return LensPage(lines: detailLines(opened), anchor: .top) }
        guard !items.isEmpty else { return LensPage(lines: [HudText.t(.savedHint)], anchor: .top) }
        let list = items.enumerated().map { index, item in
            let tag = HudText.t(item.kind == .aiChat ? .savedAiTag : .savedTalkTag)
            return "\(index + 1). [\(tag)] \(item.title)"
        }
        return LensPage(lines: list, anchor: .top)
    }

    private func detailLines(_ opened: OpenItem) -> [String] {
        var result = [opened.item.title, "──"]
        if opened.translating { result.append(HudText.t(.translating)) }
        if opened.translationFailed { result.append(HudText.t(.translationFailed)) }
        for (index, line) in opened.lines.enumerated() {
            result.append(line)
            if let translation = opened.translations?[index], !translation.isEmpty {
                result.append("  → \(translation)")
            }
        }
        return result
    }

    // MARK: - Voice actions

    func open(number: Int) -> Bool {
        guard items.indices.contains(number - 1) else { return false }
        let item = items[number - 1]
        let text = item.kind == .aiChat ? chats.read(item.url) : conversations.read(item.url)
        var lines = text.components(separatedBy: "\n")
        let header = lines.isEmpty ? "" : lines.removeFirst()
        opened = OpenItem(item: item, language: Self.language(inHeader: header), lines: lines.filter { !$0.isEmpty })
        onChange?()
        return true
    }

    func showList() {
        opened = nil
        onChange?()
    }

    /// Translates the open item line by line (timestamps and "> " are left out).
    func translate(to requested: HudLanguage?) {
        guard var current = opened, !current.translating else { return }
        let target = requested ?? Translator.defaultTarget(for: current.language)
        current.translating = true
        current.translationFailed = false
        current.translations = nil
        opened = current
        onChange?()

        let texts = current.lines.map { Self.split($0).text }
        Task {
            let translated = try? await translator.translate(texts, from: current.language, to: target)
            guard opened?.item.url == current.item.url else { return }  // user moved on
            opened?.translating = false
            opened?.translations = translated
            opened?.translationFailed = translated == nil
            onChange?()
        }
    }

    // MARK: - Helpers

    private func reloadItems() {
        let talk = conversations.sessions.map { Item(url: $0, kind: .conversation, title: ConversationLog.title(for: $0)) }
        let ai = chats.chats.map { Item(url: $0, kind: .aiChat, title: AiChatArchive.title(for: $0)) }
        // Both titles start with "yyyy-MM-dd HH:mm", so text order is time order.
        items = (talk + ai).sorted { $0.title > $1.title }
        onChange?()
    }

    /// "2026-11-07 14:32 · 日本語 ..." -> .japanese (the language it was spoken in).
    private static func language(inHeader header: String) -> HudLanguage {
        HudLanguage.allCases.first { header.contains($0.displayName) } ?? HudText.language
    }

    /// Splits "14:32:05  text" / "> text" into the prefix and the text to translate.
    private static func split(_ line: String) -> (prefix: String, text: String) {
        if line.hasPrefix("> ") { return ("> ", String(line.dropFirst(2))) }
        if let range = line.range(of: "  "), line[..<range.lowerBound].allSatisfy({ $0.isNumber || $0 == ":" }) {
            return (String(line[..<range.upperBound]), String(line[range.upperBound...]))
        }
        return ("", line)
    }
}

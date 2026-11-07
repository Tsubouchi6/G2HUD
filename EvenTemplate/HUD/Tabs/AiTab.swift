// AiTab.swift
//
// Lens tab: plain-text AI chat. Questions show as "> question" lines, answers
// below, newest at the bottom.
//   1. Claude through the PC bridge, when set up in Settings (ClaudeOnPC).
//   2. Otherwise, or when the PC can't be reached: the iPhone's on-device AI,
//      tagged "(iPhone AI)" if Claude was supposed to answer.
// Both may search, draw charts, or show pictures by themselves.
//
// The chat on screen is what "save this chat" saves (AiChatArchive).
//
// Public API: AiTab(ai:claude:settings:archive:)  — LensTab with id "ai"; ask(_ question:)

import Foundation

@MainActor
final class AiTab: LensTab {

    let id = "ai"
    var title: String { HudText.t(.tabAI) }
    let voiceNames = ["ai", "エーアイ", "えーあい", "チャット", "chat", "質問", "ia", "inteligência artificial"]
    var onChange: (() -> Void)?

    private let ai: OnDeviceAI
    private let claude: ClaudeOnPC
    private let settings: HudSettings
    private var lines: [String] = []
    private static let maxLines = 200

    init(ai: OnDeviceAI, claude: ClaudeOnPC, settings: HudSettings, archive: AiChatArchive) {
        self.ai = ai
        self.claude = claude
        self.settings = settings
        archive.currentTranscript = { [weak self] in self?.transcriptForSaving ?? [] }
    }

    /// The chat without the pending "..." and the save request itself.
    private var transcriptForSaving: [String] {
        var result = lines
        if result.last == "..." { result.removeLast() }
        if result.last?.hasPrefix("> ") == true { result.removeLast() }
        return result
    }

    func page() -> LensPage {
        LensPage(lines: lines.isEmpty ? [HudText.t(.aiHint)] : lines, anchor: .bottom)
    }

    // MARK: - Asking

    func ask(_ question: String) {
        append(["> \(question)", "..."])
        Task {
            let answer = await answer(question)
            if lines.last == "..." { lines.removeLast() }
            append([answer])
        }
    }

    /// Claude first (if set up), the iPhone AI as fallback.
    private func answer(_ question: String) async -> String {
        var claudeFailure: Error?
        if claude.isConfigured {
            do {
                return try await claude.ask(question)
            } catch {
                claudeFailure = error
            }
        }
        if ai.availabilityMessage != nil {
            return claudeFailure.map { HudText.t(.aiError, $0.localizedDescription) } ?? HudText.t(.aiUnavailable)
        }
        do {
            let local = try await ai.ask(question, language: settings.language)
            return claudeFailure == nil ? local : "\(HudText.t(.iphoneAiTag)) \(local)"
        } catch {
            return HudText.t(.aiError, error.localizedDescription)
        }
    }

    private func append(_ newLines: [String]) {
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        onChange?()
    }
}

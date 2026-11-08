// AiTab.swift
//
// Lens tab: plain-text AI chat. Questions show as ">> question" lines, answers
// indented below them, newest at the bottom. (Stored as "> question", the
// format saved chats use.) While waiting, the dots animate . / .. / ...
//   1. Claude through the PC bridge, when set up in Settings (ClaudeOnPC).
//   2. Otherwise, or when the PC can't be reached: the iPhone's on-device AI,
//      tagged "(iPhone AI)" if Claude was supposed to answer.
// Both may search, draw charts, or show pictures by themselves.
//
// Charts and photos either AI asks for appear in the chat like a message: a
// "[▣ caption]" line plus the picture under the newest lines (LensPage.picture),
// until the next question.
// The chat on screen is what "save this chat" saves (AiChatArchive).
//
// Public API: AiTab(ai:settings:archive:)  — LensTab with id "ai"; ask(_ question:)
//   onAnswered: (() -> Void)?      // an answer appeared
//   claude: ClaudeOnPC?            // set by HudController (built after the tab, since its
//                                  // actions put pictures into this tab)
//   addPicture(_ png:, caption:)   // png must be chatPictureWidthPx x chatPictureHeightPx
//   say(_ text:)                   // Neo speaks first (directions: the next step), as an answer line

import Foundation

@MainActor
final class AiTab: LensTab {

    let id = "ai"
    var title: String { HudText.t(.tabAI) }
    let voiceNames = ["ai", "エーアイ", "えーあい", "チャット", "chat", "質問", "ia", "inteligência artificial"]
    var onChange: (() -> Void)?

    private let ai: OnDeviceAI
    var claude: ClaudeOnPC?
    /// Called when an answer appears (the listening window gives 10 s to respond).
    var onAnswered: (() -> Void)?
    private let settings: HudSettings
    private var lines: [String] = []
    /// The current answer's picture; cleared when the next question is asked.
    private var picture: Data?
    private static let maxLines = 200
    /// Thinking-dots animation while an answer is pending.
    private var thinkingFrame = 0
    private var thinkingTask: Task<Void, Never>?

    init(ai: OnDeviceAI, settings: HudSettings, archive: AiChatArchive) {
        self.ai = ai
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
        guard !lines.isEmpty else { return LensPage(lines: [HudText.t(.aiHint)], anchor: .bottom) }
        return LensPage(lines: lines.map(display), anchor: .bottom, picture: picture)
    }

    /// "> question" -> ">> question"; answers indented (every paragraph) under it;
    /// the pending "..." shows the current animation frame.
    private func display(_ line: String) -> String {
        if line.hasPrefix("> ") { return ">> " + line.dropFirst(2) }
        if line == "..." { return "   " + String(repeating: ".", count: thinkingFrame % 3 + 1) }
        return "   " + line.replacingOccurrences(of: "\n", with: "\n   ")
    }

    /// Cycles the dots until the answer replaces them.
    private func animateThinking() {
        thinkingTask?.cancel()
        thinkingFrame = 0
        thinkingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HudConstants.aiThinkingFrameSeconds))
                guard let self, !Task.isCancelled, self.lines.last == "..." else { return }
                self.thinkingFrame += 1
                self.onChange?()
            }
        }
    }

    // MARK: - Asking

    func ask(_ question: String) {
        picture = nil
        append(["> \(question)", "..."])
        animateThinking()
        Task {
            let answer = await answer(question)
            // The dots may no longer be last (a direction step said meanwhile): replace them where they are.
            if let pending = lines.lastIndex(of: "...") {
                lines[pending] = answer
                onChange?()
            } else {
                append([answer])
            }
            onAnswered?()
        }
    }

    /// Claude first (if set up), the iPhone AI as fallback.
    private func answer(_ question: String) async -> String {
        var claudeFailure: Error?
        if let claude, claude.isConfigured {
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
        } catch OnDeviceAIError.blocked {
            return HudText.t(.aiBlocked)
        } catch {
            return HudText.t(.aiError, error.localizedDescription)
        }
    }

    /// A message from Neo nobody asked for yet (the next direction step).
    func say(_ text: String) {
        // While an answer is pending, keep the "..." last so it stays under the question.
        if lines.last == "..." {
            lines.insert(text, at: lines.count - 1)
            onChange?()
        } else {
            append([text])
        }
    }

    func addPicture(_ png: Data, caption: String) {
        // Keep a pending "..." last, so the answer still replaces it.
        let pendingIndex = lines.last == "..." ? lines.count - 1 : nil
        let line = "[▣ \(caption)]"
        if let pendingIndex { lines.insert(line, at: pendingIndex) } else { lines.append(line) }
        picture = png
        onChange?()
    }

    private func append(_ newLines: [String]) {
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        onChange?()
    }
}

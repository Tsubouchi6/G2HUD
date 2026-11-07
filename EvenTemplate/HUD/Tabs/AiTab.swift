// AiTab.swift
//
// Lens tab: plain-text chat with the on-device AI. Questions show as
// "> question" lines, answers below, newest at the bottom.
//
// Public API: AiTab(ai:)  — LensTab with id "ai"; ask(_ question:)

import Foundation

@MainActor
final class AiTab: LensTab {

    let id = "ai"
    let title = "AI"
    let voiceNames = ["ai", "エーアイ", "えーあい", "チャット", "chat", "質問"]
    var onChange: (() -> Void)?

    private let ai: OnDeviceAI
    private var lines: [String] = []
    private static let maxLines = 200

    init(ai: OnDeviceAI) {
        self.ai = ai
    }

    func page() -> LensPage {
        LensPage(lines: lines.isEmpty ? ["> (ask something)"] : lines, anchor: .bottom)
    }

    // MARK: - Asking

    func ask(_ question: String) {
        if let problem = ai.availabilityMessage {
            append(["> \(question)", problem])
            return
        }
        append(["> \(question)", "..."])
        Task {
            let answer: String
            do {
                answer = try await ai.ask(question)
            } catch {
                answer = "AI error: \(error.localizedDescription)"
            }
            if lines.last == "..." { lines.removeLast() }
            append([answer])
        }
    }

    private func append(_ newLines: [String]) {
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        onChange?()
    }
}

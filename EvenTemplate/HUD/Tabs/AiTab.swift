// AiTab.swift
//
// Lens tab: plain-text chat with the on-device AI. Questions show as
// "> question" lines, answers below, newest at the bottom. The AI may search,
// draw charts, or show pictures by itself through its tools (AiTools).
//
// Public API: AiTab(ai:settings:)  — LensTab with id "ai"; ask(_ question:)

import Foundation

@MainActor
final class AiTab: LensTab {

    let id = "ai"
    var title: String { HudText.t(.tabAI) }
    let voiceNames = ["ai", "エーアイ", "えーあい", "チャット", "chat", "質問", "ia", "inteligência artificial"]
    var onChange: (() -> Void)?

    private let ai: OnDeviceAI
    private let settings: HudSettings
    private var lines: [String] = []
    private static let maxLines = 200

    init(ai: OnDeviceAI, settings: HudSettings) {
        self.ai = ai
        self.settings = settings
    }

    func page() -> LensPage {
        LensPage(lines: lines.isEmpty ? [HudText.t(.aiHint)] : lines, anchor: .bottom)
    }

    // MARK: - Asking

    func ask(_ question: String) {
        if ai.availabilityMessage != nil {
            append(["> \(question)", HudText.t(.aiUnavailable)])
            return
        }
        append(["> \(question)", "..."])
        Task {
            let answer: String
            do {
                answer = try await ai.ask(question, language: settings.language)
            } catch {
                answer = HudText.t(.aiError, error.localizedDescription)
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

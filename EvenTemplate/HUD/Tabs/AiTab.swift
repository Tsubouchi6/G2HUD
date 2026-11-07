// AiTab.swift
//
// Lens tab: plain-text chat with the on-device AI. Questions show as
// "> question" lines, answers below, newest at the bottom.
//
// When the AI's reply ends with "IMAGE: <terms>", that line is removed and
// `onWantsImage` is called so the HUD can show a matching web photo.
//
// Public API: AiTab(ai:)  — LensTab with id "ai"; ask(_ question:)
//   onWantsImage: ((_ terms: String, _ caption: String) -> Void)?

import Foundation

@MainActor
final class AiTab: LensTab {

    let id = "ai"
    var title: String { HudText.t(.tabAI) }
    let voiceNames = ["ai", "エーアイ", "えーあい", "チャット", "chat", "質問", "ia", "inteligência artificial"]
    var onChange: (() -> Void)?
    var onWantsImage: ((_ terms: String, _ caption: String) -> Void)?

    private let ai: OnDeviceAI
    private var lines: [String] = []
    private static let maxLines = 200

    init(ai: OnDeviceAI) {
        self.ai = ai
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
                answer = try await ai.ask(question)
            } catch {
                answer = HudText.t(.aiError, error.localizedDescription)
            }
            if lines.last == "..." { lines.removeLast() }
            let (text, imageTerms) = Self.splitImageRequest(answer)
            append([text])
            if let imageTerms { onWantsImage?(imageTerms, text) }
        }
    }

    /// Separates a trailing "IMAGE: terms" line from the answer text.
    private static func splitImageRequest(_ answer: String) -> (text: String, imageTerms: String?) {
        var lines = answer.components(separatedBy: "\n")
        guard let index = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(HudConstants.aiImageMarker) })
        else { return (answer, nil) }
        let terms = lines[index].trimmingCharacters(in: .whitespaces)
            .dropFirst(HudConstants.aiImageMarker.count)
            .trimmingCharacters(in: .whitespaces)
        lines.remove(at: index)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, terms.isEmpty ? nil : terms)
    }

    private func append(_ newLines: [String]) {
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        onChange?()
    }
}

// CaptionsTab.swift
//
// Lens tab: live captions. Newest phrase at the bottom; the in-progress
// phrase is shown last and replaced as the speech engine refines it.
// When the mic listens in another language than the HUD's, each finished
// phrase is shown translated into the HUD language (Translator, on-device);
// the in-progress phrase stays as heard until it's finished.
//
// Public API: CaptionsTab(captions:settings:translator:)  — a LensTab with id "captions".

import Combine
import Foundation

@MainActor
final class CaptionsTab: LensTab {

    let id = "captions"
    var title: String { HudText.t(.tabCaptions) }
    let voiceNames = ["字幕", "じまく", "キャプション", "captions", "caption", "subtitles", "legendas", "legenda"]
    var onChange: (() -> Void)?

    private let captions: CaptionController
    private let settings: HudSettings
    private let translator: Translator
    private var subscription: AnyCancellable?
    /// Heard phrase -> its translation into the HUD language.
    private var translations: [String: String] = [:]
    private var translating: Set<String> = []

    init(captions: CaptionController, settings: HudSettings, translator: Translator) {
        self.captions = captions
        self.settings = settings
        self.translator = translator
        // objectWillChange fires before the value updates; read it on the next tick.
        subscription = captions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.translateNewPhrases()
                self?.onChange?()
            }
    }

    private var needsTranslation: Bool { settings.hearingLanguage != settings.language }

    func page() -> LensPage {
        let recent = captions.phrases.suffix(HudConstants.captionPhrasesOnLens)
        var lines = needsTranslation ? recent.map { translations[$0] ?? $0 } : Array(recent)
        if !captions.livePhrase.isEmpty { lines.append(captions.livePhrase) }
        if lines.isEmpty { lines = [HudText.t(captions.isRunning ? .listening : .captionsOff)] }
        return LensPage(lines: lines, anchor: .bottom)
    }

    // MARK: - Translation

    /// Translates finished phrases not translated yet (shown as heard until done).
    private func translateNewPhrases() {
        guard needsTranslation else { return }
        let from = settings.hearingLanguage, to = settings.language
        for phrase in captions.phrases.suffix(HudConstants.captionPhrasesOnLens)
        where translations[phrase] == nil && !translating.contains(phrase) {
            translating.insert(phrase)
            Task {
                if let text = try? await translator.translate([phrase], from: from, to: to).first {
                    translations[phrase] = text
                    onChange?()
                }
                translating.remove(phrase)
            }
        }
        if translations.count > HudConstants.captionHistoryLimit { translations.removeAll() }
    }
}

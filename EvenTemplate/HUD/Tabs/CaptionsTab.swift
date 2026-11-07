// CaptionsTab.swift
//
// Lens tab: live captions. Newest phrase at the bottom; the in-progress
// phrase is shown last and replaced as the speech engine refines it.
//
// Public API: CaptionsTab(captions:)  — a LensTab with id "captions".

import Combine
import Foundation

@MainActor
final class CaptionsTab: LensTab {

    let id = "captions"
    var title: String { HudText.t(.tabCaptions) }
    let voiceNames = ["字幕", "じまく", "キャプション", "captions", "caption", "subtitles", "legendas", "legenda"]
    var onChange: (() -> Void)?

    private let captions: CaptionController
    private var subscription: AnyCancellable?

    init(captions: CaptionController) {
        self.captions = captions
        // objectWillChange fires before the value updates; read it on the next tick.
        subscription = captions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onChange?() }
    }

    func page() -> LensPage {
        var lines = Array(captions.phrases.suffix(HudConstants.captionPhrasesOnLens))
        if !captions.livePhrase.isEmpty { lines.append(captions.livePhrase) }
        if lines.isEmpty { lines = [HudText.t(captions.isRunning ? .listening : .captionsOff)] }
        return LensPage(lines: lines, anchor: .bottom)
    }
}

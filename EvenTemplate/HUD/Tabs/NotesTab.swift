// NotesTab.swift
//
// Lens tab: the user's notes, newest first (one line each, wrapped if long).
//
// Public API: NotesTab(store:)  — LensTab with id "notes".

import Combine
import Foundation

@MainActor
final class NotesTab: LensTab {

    let id = "notes"
    var title: String { HudText.t(.tabNotes) }
    let voiceNames = ["メモ", "めも", "ノート", "notes", "note", "memo", "notas", "anotações"]
    var onChange: (() -> Void)?

    private let store: NotesStore
    private var subscription: AnyCancellable?

    init(store: NotesStore) {
        self.store = store
        subscription = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onChange?() }
    }

    func page() -> LensPage {
        guard !store.notes.isEmpty else {
            return LensPage(lines: [HudText.t(.notesHint)], anchor: .top)
        }
        return LensPage(lines: store.notes.map { "・\($0.text)" }, anchor: .top)
    }
}

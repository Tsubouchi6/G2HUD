// NotesStore.swift
//
// The user's notes, kept in the app (Documents/notes.json). Newest first.
//
// Public API:
//   NotesStore()
//   @Published notes: [Note]
//   add(_ text:) / deleteNewest() / delete(id:) / deleteAll()

import Foundation

struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
}

@MainActor
final class NotesStore: ObservableObject {

    @Published private(set) var notes: [Note] = []

    private let file = JsonFileStore<[Note]>(fileName: "notes.json")

    init() {
        notes = file.load() ?? []
    }

    // MARK: - Editing

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(Note(id: UUID(), text: trimmed, createdAt: Date()), at: 0)
        file.save(notes)
    }

    func deleteNewest() {
        guard !notes.isEmpty else { return }
        notes.removeFirst()
        file.save(notes)
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        file.save(notes)
    }

    func deleteAll() {
        notes = []
        file.save(notes)
    }
}

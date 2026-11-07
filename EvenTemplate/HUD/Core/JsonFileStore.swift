// JsonFileStore.swift
//
// Saves and loads one Codable value as a JSON file in the app's Documents
// folder. Used by notes and reminders so they survive app restarts.
//
// Public API:
//   JsonFileStore<Value>(fileName:)
//   load() -> Value?
//   save(_ value: Value)

import Foundation

struct JsonFileStore<Value: Codable> {

    let fileName: String

    func load() -> Value? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let url = fileURL(), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL() -> URL? {
        let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return documents?.appendingPathComponent(fileName)
    }
}

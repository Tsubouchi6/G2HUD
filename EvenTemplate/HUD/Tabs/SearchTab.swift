// SearchTab.swift
//
// Lens tab: web search results (Brave). Each result is a title line plus a
// shortened snippet line.
//
// Public API: SearchTab(settings:)  — LensTab with id "search"; search(_ query:)

import Foundation

@MainActor
final class SearchTab: LensTab {

    let id = "search"
    let title = "検索"
    let voiceNames = ["検索", "けんさく", "サーチ", "search", "google", "グーグル"]
    var onChange: (() -> Void)?

    private let settings: HudSettings
    private var lines: [String] = ["(say: メガネ 検索 ...)"]

    init(settings: HudSettings) {
        self.settings = settings
    }

    func page() -> LensPage {
        LensPage(lines: lines, anchor: .top)
    }

    // MARK: - Searching

    func search(_ query: String) {
        lines = ["検索: \(query)", "..."]
        onChange?()
        let apiKey = settings.braveApiKey
        Task {
            do {
                let results = try await BraveSearchClient.search(query, apiKey: apiKey)
                show(query: query, results: results)
            } catch {
                lines = ["検索: \(query)", error.localizedDescription]
                onChange?()
            }
        }
    }

    private func show(query: String, results: [SearchResult]) {
        guard !results.isEmpty else {
            lines = ["検索: \(query)", "No results"]
            onChange?()
            return
        }
        let snippetUnits = HudConstants.lensLineUnits * 2 - 3
        lines = ["検索: \(query)"] + results.enumerated().flatMap { index, result in
            [
                "\(index + 1). \(LensTextLayout.truncate(result.title, units: HudConstants.lensLineUnits - 3))",
                "   " + LensTextLayout.truncate(result.snippet, units: snippetUnits),
            ]
        }
        onChange?()
    }
}

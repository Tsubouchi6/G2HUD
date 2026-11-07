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
    var title: String { HudText.t(.tabSearch) }
    let voiceNames = ["検索", "けんさく", "サーチ", "search", "google", "グーグル", "pesquisa", "busca"]
    var onChange: (() -> Void)?

    private let settings: HudSettings
    private var lines: [String] = []

    init(settings: HudSettings) {
        self.settings = settings
    }

    func page() -> LensPage {
        LensPage(lines: lines.isEmpty ? [HudText.t(.searchHint)] : lines, anchor: .top)
    }

    // MARK: - Searching

    func search(_ query: String) {
        lines = [HudText.t(.searchLabel, query), "..."]
        onChange?()
        let apiKey = settings.braveApiKey
        Task {
            do {
                let results = try await BraveSearchClient.search(query, apiKey: apiKey)
                show(query: query, results: results)
            } catch {
                lines = [HudText.t(.searchLabel, query), error.localizedDescription]
                onChange?()
            }
        }
    }

    private func show(query: String, results: [SearchResult]) {
        guard !results.isEmpty else {
            lines = [HudText.t(.searchLabel, query), HudText.t(.noResults)]
            onChange?()
            return
        }
        let snippetUnits = HudConstants.lensLineUnits * 2 - 3
        lines = [HudText.t(.searchLabel, query)] + results.enumerated().flatMap { index, result in
            [
                "\(index + 1). \(LensTextLayout.truncate(result.title, units: HudConstants.lensLineUnits - 3))",
                "   " + LensTextLayout.truncate(result.snippet, units: snippetUnits),
            ]
        }
        onChange?()
    }
}

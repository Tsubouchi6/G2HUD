// SearchTab.swift
//
// Lens tab: web search. Shows the query, a short AI summary (from Tavily, or
// the on-device AI's offline answer when Tavily is unavailable), then result titles.
//
// Public API: SearchTab(service:)  — LensTab with id "search"; search(_ query:)

import Foundation

@MainActor
final class SearchTab: LensTab {

    let id = "search"
    var title: String { HudText.t(.tabSearch) }
    let voiceNames = ["検索", "けんさく", "サーチ", "search", "google", "グーグル", "pesquisa", "busca"]
    var onChange: (() -> Void)?

    private let service: WebSearchService
    private var lines: [String] = []

    init(service: WebSearchService) {
        self.service = service
    }

    func page() -> LensPage {
        LensPage(lines: lines.isEmpty ? [HudText.t(.searchHint)] : lines, anchor: .top)
    }

    // MARK: - Searching

    func search(_ query: String) {
        show([HudText.t(.searchLabel, query), "..."])
        Task {
            do {
                let outcome = try await service.search(query)
                show(Self.format(query: query, outcome: outcome))
            } catch SearchError.missingApiKey {
                show([HudText.t(.searchLabel, query), HudText.t(.noSearchKey)])
            } catch {
                show([HudText.t(.searchLabel, query), error.localizedDescription])
            }
        }
    }

    private func show(_ newLines: [String]) {
        lines = newLines
        onChange?()
    }

    // MARK: - Formatting

    /// Query, summary, a divider, then one title line per result.
    private static func format(query: String, outcome: SearchOutcome) -> [String] {
        var result = [HudText.t(.searchLabel, query)]
        if let summary = outcome.summary {
            result.append(outcome.isOffline ? "\(HudText.t(.offlineTag)) \(summary)" : summary)
        }
        guard !outcome.results.isEmpty else {
            if outcome.summary == nil { result.append(HudText.t(.noResults)) }
            return result
        }
        result.append("──")
        let titleUnits = HudConstants.lensLineUnits - 3
        for (index, item) in outcome.results.enumerated() {
            result.append("\(index + 1). \(LensTextLayout.truncate(item.title, units: titleUnits))")
        }
        return result
    }
}

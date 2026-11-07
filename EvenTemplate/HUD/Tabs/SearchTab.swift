// SearchTab.swift
//
// Lens tab: web search. The query sits in the tab bar; the lens shows a short
// AI summary (from Tavily, or the on-device AI's offline answer when Tavily is
// unavailable), then numbered result titles.
//
// Public API: SearchTab(service:)  — LensTab with id "search"; search(_ query:)
//   onFinished: (() -> Void)?   // results or an error appeared

import Foundation

@MainActor
final class SearchTab: LensTab {

    let id = "search"
    var title: String { HudText.t(.tabSearch) }
    let voiceNames = ["検索", "けんさく", "サーチ", "search", "google", "グーグル", "pesquisa", "busca"]
    var onChange: (() -> Void)?
    /// Called when results (or an error) appear.
    var onFinished: (() -> Void)?

    private let service: WebSearchService
    private var lines: [String] = []
    private var query: String?

    init(service: WebSearchService) {
        self.service = service
    }

    func page() -> LensPage {
        LensPage(lines: lines.isEmpty ? [HudText.t(.searchHint)] : lines, anchor: .top,
                 header: query.map { HudText.t(.searchLabel, $0) })
    }

    // MARK: - Searching

    func search(_ query: String) {
        self.query = query
        show(["..."])
        Task {
            do {
                let outcome = try await service.search(query)
                show(Self.format(outcome))
            } catch SearchError.missingApiKey {
                show([HudText.t(.noSearchKey)])
            } catch {
                show([error.localizedDescription])
            }
            onFinished?()
        }
    }

    private func show(_ newLines: [String]) {
        lines = newLines
        onChange?()
    }

    // MARK: - Formatting

    /// Summary, then one numbered title line per result.
    private static func format(_ outcome: SearchOutcome) -> [String] {
        var result: [String] = []
        if let summary = outcome.summary {
            result.append(outcome.isOffline ? "\(HudText.t(.offlineTag)) \(summary)" : summary)
        }
        guard !outcome.results.isEmpty else {
            if outcome.summary == nil { result.append(HudText.t(.noResults)) }
            return result
        }
        let titleUnits = HudConstants.lensLineUnits - 3
        for (index, item) in outcome.results.enumerated() {
            result.append("\(index + 1). \(LensTextLayout.truncate(item.title, units: titleUnits))")
        }
        return result
    }
}

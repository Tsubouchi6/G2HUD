// SearchTab.swift
//
// Lens tab: web search. Shows the query, a short AI summary (from Tavily, or
// the on-device AI's offline answer when Tavily is unavailable), then result titles.
//
// When the query asks for a picture ("画像", "photo of", "foto"...), the first
// web photo is downloaded and handed to `onImage` with the summary as caption.
//
// Public API: SearchTab(service:)  — LensTab with id "search"; search(_ query:)
//   onImage: ((_ data: Data, _ caption: String) -> Void)?

import Foundation

@MainActor
final class SearchTab: LensTab {

    let id = "search"
    var title: String { HudText.t(.tabSearch) }
    let voiceNames = ["検索", "けんさく", "サーチ", "search", "google", "グーグル", "pesquisa", "busca"]
    var onChange: (() -> Void)?
    var onImage: ((_ data: Data, _ caption: String) -> Void)?

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
                let wantsPicture = VoicePhrases.wantsPicture(query)
                let outcome = try await service.search(query, includeImages: wantsPicture)
                show(Self.format(query: query, outcome: outcome))
                if wantsPicture, let data = await service.download(outcome.imageURLs) {
                    onImage?(data, outcome.summary ?? query)
                }
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

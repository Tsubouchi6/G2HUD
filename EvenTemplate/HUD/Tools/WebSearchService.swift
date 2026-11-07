// WebSearchService.swift
//
// Picks the search provider and makes sure every search comes with a short
// AI summary:
//   1. Tavily (search + its own AI answer) when a Tavily key is set.
//   2. If Tavily fails or its free quota is used up: Brave Search, then the
//      on-device AI summarizes Brave's snippets.
//
// Public API:
//   WebSearchService(settings:ai:)
//   search(_ query: String) async throws -> SearchOutcome

import Foundation

/// One search's result: an optional AI summary plus the raw results.
struct SearchOutcome {
    let summary: String?
    let results: [SearchResult]
    /// Shown on the phone for debugging, e.g. "Tavily".
    let provider: String
}

@MainActor
final class WebSearchService {

    private let settings: HudSettings
    private let ai: OnDeviceAI

    init(settings: HudSettings, ai: OnDeviceAI) {
        self.settings = settings
        self.ai = ai
    }

    func search(_ query: String) async throws -> SearchOutcome {
        let tavilyKey = settings.tavilyApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let braveKey = settings.braveApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !tavilyKey.isEmpty {
            do {
                return try await TavilySearchClient.search(
                    query, apiKey: tavilyKey, languageCode: settings.language.rawValue
                )
            } catch {
                // Quota used up, network or server error: fall back if possible.
                guard !braveKey.isEmpty else { throw error }
            }
        }

        guard !braveKey.isEmpty else { throw SearchError.missingApiKey }
        let results = try await BraveSearchClient.search(query, apiKey: braveKey)
        let summary = try? await ai.summarize(query: query, results: results, language: settings.language)
        return SearchOutcome(summary: summary, results: results, provider: "Brave + on-device AI")
    }
}

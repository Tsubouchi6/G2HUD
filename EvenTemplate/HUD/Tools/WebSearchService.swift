// WebSearchService.swift
//
// Runs a search and makes sure it comes back with a short answer:
//   1. Tavily (search + its own AI answer) — free 1,000 searches/month.
//   2. If Tavily fails or the free quota is used up: the on-device AI answers
//      from its own knowledge, marked "offline" (it can't see the live web).
//
// Public API:
//   WebSearchService(settings:ai:)
//   search(_ query: String) async throws -> SearchOutcome
//   struct SearchOutcome, struct SearchResult, enum SearchError

import Foundation

// MARK: - Shared types

struct SearchResult: Equatable {
    let title: String
    let url: String
    let snippet: String
}

/// One search's result: an optional AI summary plus the raw results.
struct SearchOutcome {
    let summary: String?
    let results: [SearchResult]
    /// Which path answered, e.g. "Tavily" or "offline AI".
    let provider: String
    /// True when the answer came from the on-device AI's memory, not the web.
    let isOffline: Bool
}

enum SearchError: LocalizedError {
    case missingApiKey
    case quotaExceeded
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Add a Tavily API key in Settings"
        case .quotaExceeded: return "Search quota used up"
        case .badResponse(let code): return "Search failed (HTTP \(code))"
        }
    }
}

// MARK: - Service

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
        guard !tavilyKey.isEmpty else { throw SearchError.missingApiKey }

        do {
            return try await TavilySearchClient.search(
                query, apiKey: tavilyKey, languageCode: settings.language.rawValue
            )
        } catch {
            // Quota used up, network or server error: answer offline if the
            // on-device AI is available, otherwise report the original error.
            guard ai.availabilityMessage == nil,
                  let answer = try? await ai.answerOffline(query: query, language: settings.language)
            else { throw error }
            return SearchOutcome(summary: answer, results: [], provider: "offline AI", isOffline: true)
        }
    }
}

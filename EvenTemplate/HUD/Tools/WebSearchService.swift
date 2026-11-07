// WebSearchService.swift
//
// Runs a search and makes sure it comes back with a short answer:
//   1. Tavily (search + its own AI answer) — free 1,000 searches/month. Its
//      answer is English and can be long, so the on-device AI rewrites it
//      short, in the HUD language.
//   2. If Tavily fails or the free quota is used up: the on-device AI answers
//      from its own knowledge, marked "offline" (it can't see the live web).
//
// Public API:
//   WebSearchService(settings:ai:)
//   search(_ query: String, includeImages: Bool, condense: Bool) async throws -> SearchOutcome
//   findImage(_ terms: String) async -> Data?      // first web photo for the terms, downloaded
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
    /// Web photos for the query (only when requested).
    let imageURLs: [URL]
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

    /// `condense: false` keeps Tavily's full answer (charts need every number).
    func search(_ query: String, includeImages: Bool = false, condense: Bool = true) async throws -> SearchOutcome {
        let tavilyKey = settings.tavilyApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tavilyKey.isEmpty else { throw SearchError.missingApiKey }

        let outcome: SearchOutcome
        do {
            outcome = try await TavilySearchClient.search(
                query, apiKey: tavilyKey, languageCode: settings.language.rawValue, includeImages: includeImages
            )
        } catch {
            // Quota used up, network or server error: answer offline if the
            // on-device AI is available, otherwise report the original error.
            guard ai.availabilityMessage == nil,
                  let answer = try? await ai.answerOffline(query: query, language: settings.language)
            else { throw error }
            return SearchOutcome(summary: answer, results: [], imageURLs: [], provider: "offline AI", isOffline: true)
        }
        return condense ? await condensed(outcome, query: query) : outcome
    }

    /// Tavily's answer is English and can be long; the on-device AI rewrites it
    /// short and in the HUD language. Keeps the original if the AI is unavailable.
    private func condensed(_ outcome: SearchOutcome, query: String) async -> SearchOutcome {
        guard let summary = outcome.summary, ai.availabilityMessage == nil,
              let short = try? await ai.condense(answer: summary, query: query, language: settings.language),
              !short.isEmpty
        else { return outcome }
        return SearchOutcome(
            summary: short, results: outcome.results, imageURLs: outcome.imageURLs,
            provider: outcome.provider, isOffline: outcome.isOffline
        )
    }

    // MARK: - Images

    /// Looks up a photo for `terms` (1 Tavily credit) and downloads the first
    /// usable one. nil if there's no key, no image, or the download fails.
    func findImage(_ terms: String) async -> Data? {
        let key = settings.tavilyApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              let outcome = try? await TavilySearchClient.search(
                  terms, apiKey: key, languageCode: "en", includeAnswer: false, includeImages: true, maxResults: 1
              )
        else { return nil }
        return await download(outcome.imageURLs)
    }

    /// Downloads the first URL that returns a reasonably sized image.
    func download(_ urls: [URL]) async -> Data? {
        for url in urls.prefix(3) {
            let request = URLRequest(url: url, timeoutInterval: HudConstants.searchTimeoutSeconds)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= HudConstants.imageMaxDownloadBytes,
                  !LensImageTiler.tiles(from: data).isEmpty
            else { continue }
            return data
        }
        return nil
    }
}

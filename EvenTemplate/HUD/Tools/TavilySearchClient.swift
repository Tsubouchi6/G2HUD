// TavilySearchClient.swift
//
// Web search + AI-written answer through the Tavily API (free tier:
// 1,000 basic searches/month). The API key is entered in Settings.
// Source: docs.tavily.com/api-reference/endpoint/search
//
// Public API:
//   TavilySearchClient.search(_ query:, apiKey:, languageCode:) async throws -> SearchOutcome
//   (throws SearchError.quotaExceeded on HTTP 432/433 so the caller can fall back)

import Foundation

enum TavilySearchClient {

    // MARK: - Request / response shapes

    private struct Request: Encodable {
        let query: String
        let search_depth: String
        let include_answer: String
        let max_results: Int
        let language: String
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let title: String?
            let url: String?
            let content: String?
        }
        let answer: String?
        let results: [Item]?
    }

    // MARK: - Search

    static func search(_ query: String, apiKey: String, languageCode: String) async throws -> SearchOutcome {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let url = URL(string: HudConstants.tavilySearchEndpoint) else {
            throw SearchError.missingApiKey
        }

        var request = URLRequest(url: url, timeoutInterval: HudConstants.searchTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Request(
            query: query,
            search_depth: HudConstants.tavilySearchDepth,  // "basic" = 1 credit
            include_answer: "basic",
            max_results: HudConstants.searchResultCount,
            language: languageCode
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 432, 433: throw SearchError.quotaExceeded  // plan / pay-as-you-go limit reached
        default: throw SearchError.badResponse(status)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let results = (decoded.results ?? []).map {
            SearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.content ?? "")
        }
        let answer = decoded.answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchOutcome(summary: answer?.isEmpty == false ? answer : nil, results: results, provider: "Tavily")
    }
}

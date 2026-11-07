// BraveSearchClient.swift
//
// Web search through the Brave Search API (free tier: $5 credit/month,
// about 1,000 searches). Results only, no AI: WebSearchService uses it as the
// fallback when Tavily is unavailable and has the on-device AI summarize it.
// The API key is entered in the app's Settings tab.
//
// Public API:
//   BraveSearchClient.search(_ query: String, apiKey: String) async throws -> [SearchResult]
//   struct SearchResult { title, url, snippet }
//   enum SearchError (shared by all search clients)

import Foundation

struct SearchResult: Equatable {
    let title: String
    let url: String
    let snippet: String
}

enum SearchError: LocalizedError {
    case missingApiKey
    case quotaExceeded
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Add a Tavily or Brave API key in Settings"
        case .quotaExceeded: return "Search quota used up"
        case .badResponse(let code): return "Search failed (HTTP \(code))"
        }
    }
}

enum BraveSearchClient {

    // MARK: - Response shape (only the fields we use)

    private struct Response: Decodable {
        struct Web: Decodable { let results: [Item]? }
        struct Item: Decodable {
            let title: String?
            let url: String?
            let description: String?
        }
        let web: Web?
    }

    // MARK: - Search

    static func search(_ query: String, apiKey: String) async throws -> [SearchResult] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SearchError.missingApiKey }

        var components = URLComponents(string: HudConstants.braveSearchEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(HudConstants.searchResultCount)),
        ]
        guard let url = components?.url else { throw SearchError.badResponse(0) }

        var request = URLRequest(url: url, timeoutInterval: HudConstants.searchTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SearchError.badResponse(status) }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.web?.results ?? []).map {
            SearchResult(
                title: stripTags($0.title ?? ""),
                url: $0.url ?? "",
                snippet: stripTags($0.description ?? "")
            )
        }
    }

    /// Brave marks matches with <strong>; the lens can't show HTML.
    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }
}

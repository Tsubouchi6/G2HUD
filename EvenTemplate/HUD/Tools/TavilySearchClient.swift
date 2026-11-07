// TavilySearchClient.swift
//
// Web search + AI-written answer through the Tavily API (free tier:
// 1,000 basic searches/month). The API key is entered in Settings.
// Source: docs.tavily.com/api-reference/endpoint/search
//
// Public API:
//   TavilySearchClient.search(_ query:, apiKey:, languageCode:, includeImages:, maxResults:) async throws -> SearchOutcome
//   (throws SearchError.quotaExceeded on HTTP 432/433 so the caller can fall back)

import Foundation

enum TavilySearchClient {

    // MARK: - Request / response shapes

    private struct Request: Encodable {
        let query: String
        let search_depth: String
        let include_answer: Bool
        let include_images: Bool
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
        /// Image URLs: plain strings, or {url, description} objects when
        /// descriptions are on. Both shapes are accepted so decoding never fails.
        let images: [ImageItem]?
    }

    private struct ImageItem: Decodable {
        let url: String

        init(from decoder: Decoder) throws {
            if let plain = try? decoder.singleValueContainer().decode(String.self) {
                url = plain
                return
            }
            struct Object: Decodable { let url: String }
            url = try Object(from: decoder).url
        }
    }

    // MARK: - Search

    static func search(
        _ query: String,
        apiKey: String,
        languageCode: String,
        includeAnswer: Bool = true,
        includeImages: Bool = false,
        maxResults: Int = HudConstants.searchResultCount
    ) async throws -> SearchOutcome {
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
            include_answer: includeAnswer,
            include_images: includeImages,
            max_results: maxResults,
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
        let imageURLs = (decoded.images ?? []).compactMap { URL(string: $0.url) }.filter { $0.scheme == "https" }
        return SearchOutcome(
            summary: answer?.isEmpty == false ? answer : nil, results: results, imageURLs: imageURLs,
            provider: "Tavily", isOffline: false
        )
    }
}

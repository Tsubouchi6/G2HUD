// StockClient.swift
//
// Stock prices from Yahoo Finance's public chart feed (free, no account or
// key; unofficial, so it may change without notice). Yahoo rejects non-browser
// User-Agents, so a browser one is sent.
// Sources: query1.finance.yahoo.com/v8/finance/chart (dev.to/avabuildsdata,
// 2026), /v1/finance/search for name -> ticker.
//
// Public API:
//   StockClient.lookupSymbol(_ name: String) async throws -> String?   // "toyota" -> "7203.T"
//   StockClient.history(symbol:range:) async throws -> StockHistory
//   enum StockRange: day / week / month / year / fiveYears
//   struct StockHistory { symbol, name, currency, price, points }

import Foundation

enum StockRange: String, CaseIterable {
    case day, week, month, year, fiveYears

    /// Yahoo `range` and `interval` parameters.
    var query: (range: String, interval: String) {
        switch self {
        case .day: return ("1d", "5m")
        case .week: return ("5d", "30m")
        case .month: return ("1mo", "1d")
        case .year: return ("1y", "1wk")
        case .fiveYears: return ("5y", "1mo")
        }
    }

    /// Short label for captions.
    var label: String {
        switch self {
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .year: return "1Y"
        case .fiveYears: return "5Y"
        }
    }
}

struct StockHistory {
    let symbol: String
    let name: String
    let currency: String
    let price: Double
    /// Closing prices over the range, oldest first (gaps removed).
    let points: [(date: Date, value: Double)]
}

enum StockError: LocalizedError {
    case notFound
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Stock not found"
        case .badResponse(let code): return "Stock data failed (HTTP \(code))"
        }
    }
}

enum StockClient {

    // MARK: - Symbol lookup

    private struct SearchResponse: Decodable {
        struct Quote: Decodable {
            let symbol: String?
            let quoteType: String?
        }
        let quotes: [Quote]?
    }

    /// Finds the ticker for a company name ("apple" -> "AAPL"). nil if none.
    static func lookupSymbol(_ name: String) async throws -> String? {
        var components = URLComponents(string: HudConstants.yahooSearchEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "quotesCount", value: "5"),
            URLQueryItem(name: "newsCount", value: "0"),
        ]
        guard let url = components?.url else { return nil }
        let data = try await get(url)
        let quotes = try JSONDecoder().decode(SearchResponse.self, from: data).quotes ?? []
        let tradable = ["EQUITY", "ETF", "INDEX", "CURRENCY", "CRYPTOCURRENCY", "MUTUALFUND", "FUTURE"]
        return quotes.first { tradable.contains($0.quoteType ?? "") }?.symbol ?? quotes.first?.symbol
    }

    // MARK: - History

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            let meta: Meta
            let timestamp: [Double]?
            let indicators: Indicators
        }
        struct Meta: Decodable {
            let symbol: String?
            let currency: String?
            let regularMarketPrice: Double?
            let shortName: String?
            let longName: String?
        }
        struct Indicators: Decodable { let quote: [Quote]? }
        struct Quote: Decodable { let close: [Double?]? }
        let chart: Chart
    }

    static func history(symbol: String, range: StockRange) async throws -> StockHistory {
        let path = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        var components = URLComponents(string: HudConstants.yahooChartEndpoint + path)
        components?.queryItems = [
            URLQueryItem(name: "range", value: range.query.range),
            URLQueryItem(name: "interval", value: range.query.interval),
        ]
        guard let url = components?.url else { throw StockError.notFound }
        let data = try await get(url)

        guard let result = try JSONDecoder().decode(ChartResponse.self, from: data).chart.result?.first else {
            throw StockError.notFound
        }
        let times = result.timestamp ?? []
        let closes = result.indicators.quote?.first?.close ?? []
        let points = zip(times, closes).compactMap { time, close -> (date: Date, value: Double)? in
            guard let close else { return nil }
            return (Date(timeIntervalSince1970: time), close)
        }
        guard let price = result.meta.regularMarketPrice ?? points.last?.value else { throw StockError.notFound }

        return StockHistory(
            symbol: result.meta.symbol ?? symbol,
            name: result.meta.shortName ?? result.meta.longName ?? symbol,
            currency: result.meta.currency ?? "",
            price: price,
            points: points
        )
    }

    // MARK: - HTTP

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: HudConstants.searchTimeoutSeconds)
        request.setValue(HudConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw StockError.badResponse(status) }
        return data
    }
}

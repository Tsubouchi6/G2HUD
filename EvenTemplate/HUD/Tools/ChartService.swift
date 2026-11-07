// ChartService.swift
//
// Turns a spoken request into a chart picture for the lens.
//   Stocks: subject -> English name (on-device AI) -> Yahoo ticker -> price
//           history -> line chart. Free, no key.
//   Statistics: Tavily search (1 credit) -> on-device AI pulls only numbers
//           found in the results -> bar chart (<= 8 points) or line chart.
//
// Public API:
//   ChartService(search:ai:)
//   stockChart(for command: String) async throws -> RenderedChart
//   statsChart(for command: String) async throws -> RenderedChart
//   struct RenderedChart { png, caption }
//   enum ChartError: stockNotFound / noData

import Foundation

struct RenderedChart {
    let png: Data
    let caption: String
}

enum ChartError: Error {
    case stockNotFound
    case noData
}

@MainActor
final class ChartService {

    private let search: WebSearchService
    private let ai: OnDeviceAI

    init(search: WebSearchService, ai: OnDeviceAI) {
        self.search = search
        self.ai = ai
    }

    // MARK: - Stocks

    func stockChart(for command: String) async throws -> RenderedChart {
        let range = VoicePhrases.stockRange(command)
        let subject = VoicePhrases.stripChartWords(command)
        guard let symbol = await findSymbol(subject.isEmpty ? command : subject) else {
            throw ChartError.stockNotFound
        }
        let history = try await StockClient.history(symbol: symbol, range: range)
        guard history.points.count >= 2 else { throw ChartError.noData }

        let points = history.points.map { ChartPoint(label: Self.dateLabel($0.date, range: range), value: $0.value) }
        guard let png = ChartRenderer.png(points: points, kind: .line) else { throw ChartError.noData }
        return RenderedChart(png: png, caption: Self.stockCaption(history, range: range))
    }

    /// Yahoo search on the English name; falls back to the raw words
    /// (works for "apple", "AAPL") when the AI is off or its name misses.
    private func findSymbol(_ subject: String) async -> String? {
        var candidates: [String] = []
        if ai.availabilityMessage == nil, let english = try? await ai.englishAssetName(subject), !english.isEmpty {
            candidates.append(english)
        }
        candidates.append(subject)
        for name in candidates {
            if let symbol = try? await StockClient.lookupSymbol(name) { return symbol }
        }
        return nil
    }

    /// "AAPL 227.50 USD ▲+1.2% · 1M"
    private static func stockCaption(_ history: StockHistory, range: StockRange) -> String {
        let first = history.points.first?.value ?? history.price
        let changePct = first == 0 ? 0 : (history.price - first) / first * 100
        let arrow = changePct >= 0 ? "▲" : "▼"
        let price = String(format: "%.2f", history.price)
        let change = String(format: "%+.1f%%", changePct)
        return "\(history.symbol) \(price) \(history.currency) \(arrow)\(change) · \(range.label)"
    }

    private static func dateLabel(_ date: Date, range: StockRange) -> String {
        let formatter = DateFormatter()
        switch range {
        case .day: formatter.dateFormat = "HH:mm"
        case .week, .month: formatter.dateFormat = "M/d"
        case .year: formatter.dateFormat = "yyyy/M"
        case .fiveYears: formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: date)
    }

    // MARK: - Statistics

    func statsChart(for command: String) async throws -> RenderedChart {
        guard ai.availabilityMessage == nil else { throw ChartError.noData }
        let outcome = try await search.search(command)
        guard !outcome.isOffline else { throw ChartError.noData }   // offline AI has no real numbers

        let sourceText = ([outcome.summary ?? ""] + outcome.results.map(\.snippet)).joined(separator: "\n")
        let series = try await ai.extractSeries(question: command, text: sourceText)
        guard series.points.count >= 2 else { throw ChartError.noData }

        let kind: ChartKind = series.points.count > HudConstants.chartMaxBars ? .line : .bar
        guard let png = ChartRenderer.png(points: series.points, kind: kind) else { throw ChartError.noData }
        let caption = series.unit.isEmpty ? series.title : "\(series.title) (\(series.unit))"
        return RenderedChart(png: png, caption: caption)
    }
}

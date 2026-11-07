// ChartService.swift
//
// Builds chart pictures for the lens. Called by the on-device AI's tools
// (AiTools), which supply the subject and numbers already understood.
//   Stocks: English name -> Yahoo ticker -> price history -> line chart (free).
//   Numbers: title + points -> bar chart (<= chartMaxBars points) or line chart.
//
// Public API:
//   ChartService()
//   stockChart(name:range:) async throws -> RenderedChart
//   chart(title:unit:points:) throws -> RenderedChart
//   struct RenderedChart { png, caption }
//   enum ChartError: stockNotFound / noData

import Foundation

struct RenderedChart: Sendable {
    let png: Data
    let caption: String
}

enum ChartError: LocalizedError {
    case stockNotFound
    case noData

    var errorDescription: String? {
        switch self {
        case .stockNotFound: return "Stock not found"
        case .noData: return "No numbers to chart"
        }
    }
}

@MainActor
final class ChartService {

    // MARK: - Stocks

    func stockChart(name: String, range: StockRange) async throws -> RenderedChart {
        guard let symbol = try await StockClient.lookupSymbol(name) else { throw ChartError.stockNotFound }
        let history = try await StockClient.history(symbol: symbol, range: range)
        guard history.points.count >= 2 else { throw ChartError.noData }

        let points = history.points.map { ChartPoint(label: Self.dateLabel($0.date, range: range), value: $0.value) }
        guard let png = ChartRenderer.png(points: points, kind: .line) else { throw ChartError.noData }
        return RenderedChart(png: png, caption: Self.stockCaption(history, range: range))
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

    // MARK: - Numbers

    func chart(title: String, unit: String, points: [ChartPoint]) throws -> RenderedChart {
        guard points.count >= 2 else { throw ChartError.noData }
        let kind: ChartKind = points.count > HudConstants.chartMaxBars ? .line : .bar
        guard let png = ChartRenderer.png(points: points, kind: kind) else { throw ChartError.noData }
        let caption = unit.isEmpty ? title : "\(title) (\(unit))"
        return RenderedChart(png: png, caption: caption)
    }
}

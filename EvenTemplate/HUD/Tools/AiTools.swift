// AiTools.swift
//
// Tools the on-device AI may call on its own (Foundation Models tool calling).
// The model decides from the question whether it needs one; anything it can
// answer itself (the time, the date, general knowledge) it answers directly.
// Source: developer.apple.com/documentation/foundationmodels/tool
//
// Public API:
//   AiTools.make(search:charts:showChart:showPicture:) -> [any Tool]
//     searchWeb    — live or recent facts (Tavily, 1 credit)
//     stockChart   — price chart from Yahoo Finance (free)
//     drawChart    — bar/line chart from numbers the model already has
//     showPicture  — a web photo on the lens (Tavily, 1 credit)
//   Failures are returned to the model as "Failed: ..." text, not thrown.

import Foundation
import FoundationModels

@MainActor
enum AiTools {

    static func make(
        search: WebSearchService,
        charts: ChartService,
        showChart: @escaping @MainActor @Sendable (RenderedChart) -> Void,
        showPicture: @escaping @MainActor @Sendable (_ terms: String, _ caption: String) -> Void
    ) -> [any Tool] {
        [
            SearchWebTool(search: search),
            StockChartTool(charts: charts, show: showChart),
            DrawChartTool(charts: charts, show: showChart),
            ShowPictureTool(show: showPicture),
        ]
    }

    /// Tool failures go back to the model as text, so it can tell the user
    /// in their language (e.g. "add a Tavily key in Settings").
    nonisolated static func failure(_ error: Error) -> String {
        "Failed: \(error.localizedDescription)"
    }
}

// MARK: - Web search

private struct SearchWebTool: Tool {
    let name = "searchWeb"
    let description = """
    Searches the web. Use only for live or recent information you cannot know: \
    weather, news, prices, opening hours, scores, recent events, or facts you are unsure of.
    """
    let search: WebSearchService

    @Generable
    struct Arguments {
        @Guide(description: "Short search query. Add the user's city when the question is about their area")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let outcome = try await search.search(arguments.query, condense: false)
            let text = ([outcome.summary ?? ""] + outcome.results.map(\.snippet)).joined(separator: "\n")
            return String(text.prefix(HudConstants.aiToolResultMaxChars))
        } catch {
            return AiTools.failure(error)
        }
    }
}

// MARK: - Stock chart

private struct StockChartTool: Tool {
    let name = "stockChart"
    let description = """
    Shows a price chart on the user's glasses for a stock, index, currency pair, or \
    cryptocurrency. Returns the latest price and change.
    """
    let charts: ChartService
    let show: @MainActor @Sendable (RenderedChart) -> Void

    @Generable
    enum Period: String {
        case day, week, month, year, fiveYears
    }

    @Generable
    struct Arguments {
        @Guide(description: "English name as Yahoo Finance lists it, e.g. Toyota, Apple, Nikkei 225, USD/JPY, Bitcoin")
        let name: String
        @Guide(description: "Time span. Use month unless the user asks for another")
        let period: Period
    }

    func call(arguments: Arguments) async throws -> String {
        let range = StockRange(rawValue: arguments.period.rawValue) ?? .month
        do {
            let chart = try await charts.stockChart(name: arguments.name, range: range)
            await show(chart)
            return "Chart shown. \(chart.caption)"
        } catch {
            return AiTools.failure(error)
        }
    }
}

// MARK: - Chart from numbers

private struct DrawChartTool: Tool {
    let name = "drawChart"
    let description = """
    Shows a bar or line chart on the user's glasses. Use only real numbers from a \
    searchWeb result or the user; never invent data.
    """
    let charts: ChartService
    let show: @MainActor @Sendable (RenderedChart) -> Void

    @Generable
    struct Point {
        @Guide(description: "Short label, e.g. a year or a country (max 8 characters)")
        let label: String
        let value: Double
    }

    @Generable
    struct Arguments {
        @Guide(description: "Very short title in the user's language")
        let title: String
        @Guide(description: "Unit, e.g. %, people, USD. Empty if none")
        let unit: String
        @Guide(description: "2 to 12 data points in order")
        let points: [Point]
    }

    func call(arguments: Arguments) async throws -> String {
        let points = arguments.points.map { ChartPoint(label: String($0.label.prefix(8)), value: $0.value) }
        do {
            let chart = try await charts.chart(title: arguments.title, unit: arguments.unit, points: points)
            await show(chart)
            return "Chart shown."
        } catch {
            return AiTools.failure(error)
        }
    }
}

// MARK: - Picture

private struct ShowPictureTool: Tool {
    let name = "showPicture"
    let description = """
    Shows a web photo on the user's glasses. Use when the user asks to see something, \
    or when how something looks is the answer.
    """
    let show: @MainActor @Sendable (_ terms: String, _ caption: String) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "2-5 English search words for the photo")
        let terms: String
        @Guide(description: "Very short caption in the user's language")
        let caption: String
    }

    func call(arguments: Arguments) async throws -> String {
        await show(arguments.terms, arguments.caption)
        return "Picture requested."
    }
}

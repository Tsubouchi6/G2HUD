// AiTools.swift
//
// Tools the on-device AI may call on its own (Foundation Models tool calling).
// The model decides from the question whether it needs one; anything it can
// answer itself (the time, the date, general knowledge) it answers directly.
// Source: developer.apple.com/documentation/foundationmodels/tool
//
// Public API:
//   AiTools.make(search:charts:actions:) -> [any Tool]
//     searchWeb    — live or recent facts (Tavily, 1 credit)
//     stockChart   — price chart from Yahoo Finance (free)
//     drawChart    — bar/line chart from numbers the model already has
//     showPicture  — a web photo on the lens (Tavily, 1 credit)
//     saveChat     — saves this AI chat to the Saved tab
//     startListening / stopListening — saves what people around say, from now until stopped
//     startDirections / stopDirections — turn-by-turn to the nearest match (Apple Maps, free)
//   Failures are returned to the model as "Failed: ..." text, not thrown.

import Foundation
import FoundationModels

@MainActor
enum AiTools {

    static func make(
        search: WebSearchService,
        charts: ChartService,
        actions: AiActions
    ) -> [any Tool] {
        [
            SearchWebTool(search: search),
            StockChartTool(charts: charts, show: actions.showChart),
            DrawChartTool(charts: charts, show: actions.showChart),
            ShowPictureTool(show: actions.showPicture),
            SaveChatTool(save: actions.saveChat),
            StartListeningTool(start: actions.startListening),
            StopListeningTool(stop: actions.stopListening),
            StartDirectionsTool(start: actions.startDirections),
            StopDirectionsTool(stop: actions.stopDirections),
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

// MARK: - Save chat

private struct SaveChatTool: Tool {
    let name = "saveChat"
    let description = """
    Saves this chat (the user's questions and your answers) so the user can read it \
    later in the Saved tab. Use when the user asks, in any words, to save or keep it.
    """
    let save: @MainActor @Sendable (_ title: String) -> Bool

    @Generable
    struct Arguments {
        @Guide(description: "Very short title for the chat in the user's language, e.g. its topic")
        let title: String
    }

    func call(arguments: Arguments) async throws -> String {
        await save(arguments.title) ? "Saved." : "Failed: the chat is empty."
    }
}

// MARK: - Listening

private struct StartListeningTool: Tool {
    let name = "startListening"
    let description = """
    Starts saving the text of what people around the user say, from now on, so the \
    user can read it later in the Saved tab. Use when the user asks, in any words, \
    to listen, pay attention, or remember what someone says (a meeting, a store...).
    """
    let start: @MainActor @Sendable (_ title: String) -> Bool

    @Generable
    struct Arguments {
        @Guide(description: "Very short title in the user's language, e.g. the place or event")
        let title: String
    }

    func call(arguments: Arguments) async throws -> String {
        await start(arguments.title) ? "Listening started." : "Failed: the HUD is not running, so nothing can be heard."
    }
}

private struct StopListeningTool: Tool {
    let name = "stopListening"
    let description = """
    Stops saving what people say (started by startListening) and keeps the text. \
    Use when the user says, in any words, that they're done or you can stop listening.
    """
    let stop: @MainActor @Sendable () -> Bool

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await stop() ? "Stopped and saved." : "Nothing was being listened to."
    }
}

// MARK: - Directions

private struct StartDirectionsTool: Tool {
    let name = "startDirections"
    let description = """
    Starts turn-by-turn directions on the user's glasses to the nearest place matching \
    the destination, from where they are now. Use for any request to go somewhere or \
    find the way (e.g. nearest convenience store, a station, an address).
    """
    let start: @MainActor @Sendable (_ destination: String, _ mode: DirectionsMode, _ minimal: Bool) -> Void

    @Generable
    enum Mode: String {
        case walking, driving
    }

    @Generable
    struct Arguments {
        @Guide(description: "What or where, as a map search, in the user's words, e.g. コンビニ, convenience store, Tokyo Station")
        let destination: String
        @Guide(description: "walking unless the user says they are driving")
        let mode: Mode
        @Guide(description: "true if the user wants a clear screen with only the next direction (no map)")
        let minimal: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await start(arguments.destination, DirectionsMode(rawValue: arguments.mode.rawValue) ?? .walking, arguments.minimal)
        return "Directions starting on the glasses."
    }
}

private struct StopDirectionsTool: Tool {
    let name = "stopDirections"
    let description = "Stops the directions. Use when the user says, in any words, to stop or cancel navigation."
    let stop: @MainActor @Sendable () -> Bool

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await stop() ? "Directions stopped." : "No directions were running."
    }
}

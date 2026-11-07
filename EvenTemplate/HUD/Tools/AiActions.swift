// AiActions.swift
//
// What either AI (iPhone tools or Claude's action lines) can make the HUD do.
// Built once by HudController and handed to AiTools and ClaudeOnPC, so both
// AIs share the same behaviour.
//
// Public API: struct AiActions
//   showChart(chart)               — chart picture on the lens
//   showPicture(terms, caption)    — web photo on the lens
//   saveChat(title) -> Bool        — saves the AI chat (false = empty)
//   startListening(title, language, start, stop) -> Bool — saves what people say, listening for
//                                  `language` ("ja"/"en"/"pt"; nil = the Listen-for setting),
//                                  from `start` (nil = now) until `stop` (nil = until told)
//   stopListening() -> Bool        — ends and keeps the clip, or cancels a planned one (false = neither)
//   startDirections(destination, match, mode) — nearest match, turn-by-turn with the map in the Nav tab
//   stopDirections() -> Bool       — ends navigation (false = none running)
//   showPlace(query, match)        — "where is the nearest X": X and the user together on the map
//   directionsView(view) -> Bool   — "map" / "minimal" / "zoomIn" / "zoomOut" (false = no map running)
//   calculate(expression) -> String              — exact result line, also in the Calc tab
//   convert(value, from, to) async -> String     — units or live currency, also in the Calc tab
//   openTab(id) -> Bool                           — shows a tab (false = unknown tab)
//   setLanguage(which, language) -> Bool          — "hud" / "hearing" to "ja" / "en" / "pt"

import Foundation

struct AiActions: Sendable {
    let showChart: @MainActor @Sendable (RenderedChart) -> Void
    let showPicture: @MainActor @Sendable (_ terms: String, _ caption: String) -> Void
    let saveChat: @MainActor @Sendable (_ title: String) -> Bool
    let startListening: @MainActor @Sendable (_ title: String, _ language: String?, _ start: Date?, _ stop: Date?) -> Bool
    let stopListening: @MainActor @Sendable () -> Bool
    let startDirections: @MainActor @Sendable (_ destination: String, _ match: PlaceMatch, _ mode: DirectionsMode) -> Void
    let stopDirections: @MainActor @Sendable () -> Bool
    let showPlace: @MainActor @Sendable (_ query: String, _ match: PlaceMatch) -> Void
    let directionsView: @MainActor @Sendable (_ view: String) -> Bool
    let calculate: @MainActor @Sendable (_ expression: String) -> String
    let convert: @MainActor @Sendable (_ value: Double, _ from: String, _ to: String) async -> String
    let openTab: @MainActor @Sendable (_ id: String) -> Bool
    let setLanguage: @MainActor @Sendable (_ which: String, _ language: String) -> Bool
}

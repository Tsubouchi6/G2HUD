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
//   startListening(title) -> Bool  — saves what people say from now on (false = HUD not listening)
//   stopListening() -> Bool        — ends and keeps the clip (false = nothing was being saved)
//   startDirections(destination, mode, minimal) — nearest match, turn-by-turn in the Nav tab
//   stopDirections() -> Bool       — ends navigation (false = none running)
//   calculate(expression) -> String              — exact result line, also in the Calc tab
//   convert(value, from, to) async -> String     — units or live currency, also in the Calc tab

import Foundation

struct AiActions: Sendable {
    let showChart: @MainActor @Sendable (RenderedChart) -> Void
    let showPicture: @MainActor @Sendable (_ terms: String, _ caption: String) -> Void
    let saveChat: @MainActor @Sendable (_ title: String) -> Bool
    let startListening: @MainActor @Sendable (_ title: String) -> Bool
    let stopListening: @MainActor @Sendable () -> Bool
    let startDirections: @MainActor @Sendable (_ destination: String, _ mode: DirectionsMode, _ minimal: Bool) -> Void
    let stopDirections: @MainActor @Sendable () -> Bool
    let calculate: @MainActor @Sendable (_ expression: String) -> String
    let convert: @MainActor @Sendable (_ value: Double, _ from: String, _ to: String) async -> String
}

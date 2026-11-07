// NavBriefing.swift
//
// What the AIs are told about the Nav tab, added to every question's context
// line (AiContext), so Neo can guide the user any time: where they are, where
// they're going, and the whole plan step by step (walk to X station, take
// line Y toward Z at 06:52, get off at W, use exit V, walk N m...), with the
// step they're on marked. English, since it's for the AI, not the lens.
// Capped at navAiBriefMaxChars (the iPhone AI's context is ~4k tokens).
//
// Public API:
//   NavBriefing.summary(state:address:area:steps:stepIndex:) -> String?
//   NavBriefing.describe(_ choice:) -> String      // "Train 11 min, ¥180, JR Yamanote"

import Foundation

enum NavBriefing {

    /// `area`: where the user is now ("Jingumae, Shibuya, Tokyo"); `steps` and
    /// `stepIndex`: the route being followed (empty in place / choosing mode).
    static func summary(state: NavState, address: String?, area: String?, steps: [NavStep], stepIndex: Int) -> String? {
        let place = address.map { " (\($0))" } ?? ""
        let whereNow = area.map { " The user is now in \($0)." } ?? ""
        let text: String
        switch state {
        case .place(let info):
            text = "The Nav map shows \(info.name)\(place), \(Int(info.walkingMeters)) m away, "
                + "about \(info.walkingMinutes) min on foot; not navigating there yet.\(whereNow)"
        case .choosing(let trip):
            let list = trip.choices.enumerated().map { index, choice in
                "\(index + 1)) \(describe(choice))"
            }.joined(separator: "; ")
            let best = trip.choices[trip.recommended]
            let missing = trip.transitNote.map {
                " Train and bus routes could NOT be checked (\($0)), so do not call walking the fastest; tell the user why."
            } ?? ""
            text = "Ways to \(trip.destinationName)\(place): \(list). The app recommends \(trip.recommended + 1): "
                + "\(plan(best.route.steps, current: nil))\(missing) Waiting for the user to pick one (chooseRoute).\(whereNow)"
        case .active(let progress):
            text = "Navigating to \(progress.destinationName)\(place): \(Int(progress.remainingMeters)) m, "
                + "about \(progress.remainingMinutes) min left.\(whereNow) "
                + "Plan (follow it to guide the user; never invent stations, lines or exits): "
                + plan(steps, current: stepIndex)
        case .finding(let query):
            text = "Searching the map for \(query)."
        case .arrived(let name):
            text = "The user just arrived at \(name)."
        default:
            return nil
        }
        return String(text.prefix(HudConstants.navAiBriefMaxChars))
    }

    /// "Train 11 min, ¥180, JR Yamanote"
    static func describe(_ choice: RouteChoice) -> String {
        let kind: String
        switch choice.kind {
        case .walk: kind = "Walk"
        case .train: kind = "Train"
        case .bus: kind = "Bus"
        case .mixed: kind = "Train and bus"
        }
        let fare = choice.kind == .walk ? ", free" : choice.fare.map { ", \($0)" } ?? ""
        let lines = choice.route.rides.map(\.line).joined(separator: " > ")
        return "\(kind) \(choice.minutes) min\(fare)\(lines.isEmpty ? "" : ", \(lines)")"
    }

    /// "1) Walk to Shibuya (350 m) [done] 2) Train JR Yamanote toward Shinjuku from
    /// Shibuya at 06:52, get off at Harajuku (06:56), exit Omotesando [now] 3) ..."
    /// Finished steps are dropped on long walking routes (only the next few turns matter).
    private static func plan(_ steps: [NavStep], current: Int?) -> String {
        let useful = steps.enumerated().filter { !$0.element.instruction.isEmpty || $0.element.ride != nil }
        let firstShown = useful.count > HudConstants.navAiPlanMaxSteps
            ? max(0, (useful.firstIndex { $0.offset >= (current ?? 0) } ?? 0) - 1)
            : 0
        let lines = useful.dropFirst(firstShown).prefix(HudConstants.navAiPlanMaxSteps).enumerated().map { number, item in
            let (index, step) = item
            var mark = ""
            if let current { mark = index < current ? " [done]" : index == current ? " [now]" : "" }
            return "\(firstShown + number + 1)) \(describe(step))\(mark)"
        }
        return lines.joined(separator: " ") + " Then arrive."
    }

    private static func describe(_ step: NavStep) -> String {
        guard let ride = step.ride else { return "\(step.instruction) (\(Int(step.distanceMeters)) m)" }
        let vehicle = ride.isBus ? "Bus" : "Train"
        let toward = ride.headsign.map { " toward \($0)" } ?? ""
        let departs = ride.departs.map { " at \($0)" } ?? ""
        let arrives = ride.arrives.map { " (\($0))" } ?? ""
        let exit = ride.exitGate.map { ", exit \($0)" } ?? ""
        return "\(vehicle) \(ride.line)\(toward) from \(ride.fromStop)\(departs), get off at \(ride.toStop)\(arrives)\(exit)"
    }
}

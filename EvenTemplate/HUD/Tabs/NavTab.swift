// NavTab.swift
//
// Lens tab: turn-by-turn directions from Navigator. Two views:
//   full    — destination, distance/time left, the next turn, the one after
//   minimal — one line at the top ("120m 左折 ..."), the rest of the lens clear
// Switched by voice while this tab is open ("シンプル" / "詳しく" / "地図"),
// or the AI picks minimal when asked for a clear screen.
//
// Public API: NavTab(navigator:)  — LensTab with id "nav"

import Combine
import Foundation

@MainActor
final class NavTab: LensTab {

    let id = "nav"
    var title: String { HudText.t(.tabNav) }
    let voiceNames = ["ナビ", "なび", "道案内", "nav", "navigation", "directions", "rota", "navegação", "navegacao"]
    var onChange: (() -> Void)?

    private let navigator: Navigator
    private var subscription: AnyCancellable?

    init(navigator: Navigator) {
        self.navigator = navigator
        subscription = navigator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onChange?() }
    }

    func page() -> LensPage {
        LensPage(lines: navigator.minimal ? minimalLines() : fullLines(), anchor: .top)
    }

    // MARK: - Views

    private func fullLines() -> [String] {
        switch navigator.state {
        case .idle:
            return [HudText.t(.navHint)]
        case .finding(let query):
            return [HudText.t(.navFinding, query)]
        case .failed(let message):
            return [message]
        case .arrived(let name):
            return [HudText.t(.navArrived, name)]
        case .active(let progress):
            var lines = [
                "→ \(progress.destinationName)",
                HudText.t(.navRemaining, Self.distance(progress.remainingMeters), progress.remainingMinutes),
                "──",
                turnLine(progress),
            ]
            if let after = progress.turnAfter { lines += ["", HudText.t(.navThen, after)] }
            if progress.rerouting { lines.append(HudText.t(.navRerouting)) }
            return lines
        }
    }

    /// A single line at the top; everything else on the lens stays empty.
    private func minimalLines() -> [String] {
        switch navigator.state {
        case .active(let progress):
            return [LensTextLayout.truncate(turnLine(progress), units: HudConstants.lensLineUnits)]
        case .arrived(let name):
            return [HudText.t(.navArrived, name)]
        case .finding(let query):
            return [HudText.t(.navFinding, query)]
        case .failed(let message):
            return [LensTextLayout.truncate(message, units: HudConstants.lensLineUnits)]
        case .idle:
            return [""]
        }
    }

    /// "120m  Turn left onto ..." or "450m  到着" when only the arrival is left.
    private func turnLine(_ progress: NavProgress) -> String {
        guard let turn = progress.nextTurn else {
            return "\(Self.distance(progress.remainingMeters))  \(HudText.t(.navToArrival))"
        }
        return "\(Self.distance(progress.metersToNextTurn))  \(turn)"
    }

    /// "80m", "1.2km"
    private static func distance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int((meters / 10).rounded()) * 10)m" : String(format: "%.1fkm", meters / 1000)
    }
}

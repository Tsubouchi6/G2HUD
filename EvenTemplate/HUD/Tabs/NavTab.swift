// NavTab.swift
//
// Lens tab: turn-by-turn directions, or "where is X", from Navigator. Two views:
//   full    — map (400x200, MiniMapRenderer: Apple Maps streets, north-up, route,
//             user arrow; the biggest picture the glasses take) with two lines under it: next turn; distance/time · destination
//   minimal — one line at the top ("120m 左折 ..."), the rest of the lens clear
// Without glasses connected, an arrow from the phone's compass points to the next turn.
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
        if navigator.minimal { return LensPage(lines: minimalLines(), anchor: .top) }
        // Map view: the map as big as the glasses allow, only two lines under it.
        guard let miniMap = navigator.miniMap else { return LensPage(lines: fullLines(), anchor: .top) }
        switch navigator.state {
        case .active(let progress):
            return LensPage(lines: mapLines(progress), anchor: .top, picture: miniMap, pictureSpot: .top)
        case .place(let place):
            return LensPage(lines: placeLines(place), anchor: .top, picture: miniMap, pictureSpot: .top)
        default:
            return LensPage(lines: fullLines(), anchor: .top)
        }
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
        case .place(let place):
            return placeLines(place)
        case .active(let progress):
            // Next turn first (biggest need), then the overview, like the G2 Navigate screen.
            var lines = [turnLine(progress)]
            if let after = progress.turnAfter { lines.append(HudText.t(.navThen, after)) }
            lines += [
                "──",
                HudText.t(.navRemaining, Self.distance(progress.remainingMeters), progress.remainingMinutes),
                "→ \(progress.destinationName)",
            ]
            if progress.rerouting { lines.append(HudText.t(.navRerouting)) }
            return lines
        }
    }

    /// The line under the map: the next turn, then the minutes left.
    private func mapLines(_ progress: NavProgress) -> [String] {
        let left = progress.rerouting ? HudText.t(.navRerouting) : "\(progress.remainingMinutes)min"
        return [LensTextLayout.truncate("\(turnLine(progress)) · \(left)", units: HudConstants.lensLineUnits)]
    }

    /// "Where is X": the place and how far on foot, in one line.
    private func placeLines(_ place: PlaceInfo) -> [String] {
        let walk = HudText.t(.navPlaceWalk, Self.distance(place.walkingMeters), place.walkingMinutes)
        return [LensTextLayout.truncate("◎ \(place.name) · \(walk)", units: HudConstants.lensLineUnits)]
    }

    /// A single line at the top; everything else on the lens stays empty.
    private func minimalLines() -> [String] {
        switch navigator.state {
        case .active(let progress):
            return [LensTextLayout.truncate(turnLine(progress), units: HudConstants.lensLineUnits)]
        case .place(let place):
            return [LensTextLayout.truncate("◎ \(place.name) · \(Self.distance(place.walkingMeters))", units: HudConstants.lensLineUnits)]
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

    /// "↗ 120m  Turn left onto ..." or "↑ 450m  到着" when only the arrival is left.
    /// The arrow (phone compass, without glasses) points to the next turn point.
    private func turnLine(_ progress: NavProgress) -> String {
        let arrow = progress.relativeBearing.map { Self.arrow($0) + " " } ?? ""
        guard let turn = progress.nextTurn else {
            return "\(arrow)\(Self.distance(progress.remainingMeters))  \(HudText.t(.navToArrival))"
        }
        return "\(arrow)\(Self.distance(progress.metersToNextTurn))  \(turn)"
    }

    /// 0° = ahead ↑, 90° = right →, in 45° steps.
    private static func arrow(_ degrees: Double) -> String {
        let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
        return arrows[Int(((degrees + 22.5) / 45).rounded(.down)) % 8]
    }

    /// "80m", "1.2km"
    private static func distance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int((meters / 10).rounded()) * 10)m" : String(format: "%.1fkm", meters / 1000)
    }
}

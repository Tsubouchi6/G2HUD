// NavModels.swift
//
// The data the Nav tab works with, shared by Navigator, RoutePlanner,
// TransitService and NavTab:
//   NavRoute   — one route to follow, from Apple (walk / drive) or NAVITIME (train / bus)
//   NavStep    — one step of it; a ride step carries RideInfo
//   RouteChoice / TripChoices — the ways to get somewhere, for the user to pick
//   NavState, NavProgress, PlaceInfo — what the Nav tab shows
//   MapFrame   — what the map shows (center, reach)
// Step i's instruction describes the maneuver at the START of step i ("Turn
// left", "Take JR Yamanote"), so the "next turn" is step i+1's instruction,
// reached at the end of step i.
//
// Public API: the types below.

import CoreLocation
import Foundation
import MapKit

// MARK: - Routes

/// A train or bus ride: what to take, where to get on and off.
struct RideInfo {
    /// A bus (else some kind of train); RoutePlanner sorts choices by it.
    let isBus: Bool
    let line: String
    let headsign: String?
    let fromStop: String
    let toStop: String
    /// Local clock text ("06:52"), nil if not given.
    let departs: String?
    let arrives: String?
    /// Stops to ride; 0 when not known.
    let stopCount: Int
    /// The station exit / gate to use after getting off ("A3", "表参道口"), if known.
    let exitGate: String?
}

struct NavStep {
    /// Maneuver at the start of this step. Empty when there is none.
    let instruction: String
    let distanceMeters: Double
    let seconds: Double
    let end: CLLocation
    /// How close counts as having reached `end` (stations are big; turns are not).
    let endRadiusMeters: Double
    /// Set for train / bus steps.
    let ride: RideInfo?
}

struct NavRoute {
    let points: [CLLocationCoordinate2D]
    let steps: [NavStep]
    let distanceMeters: Double
    let seconds: Double
    /// Apple walk/drive routes can be recalculated when the user strays;
    /// transit routes can't (each recalculation would use up the monthly NAVITIME quota).
    let canReroute: Bool

    init(points: [CLLocationCoordinate2D], steps: [NavStep], distanceMeters: Double, seconds: Double, canReroute: Bool) {
        self.points = points
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.seconds = seconds
        self.canReroute = canReroute
    }

    /// An Apple Maps walking or driving route.
    @MainActor
    init(apple route: MKRoute) {
        let steps = route.steps.map { step in
            let end = DirectionsService.coordinates(of: step.polyline).last ?? step.polyline.coordinate
            return NavStep(
                instruction: step.instructions, distanceMeters: step.distance,
                seconds: route.distance > 0 ? route.expectedTravelTime * step.distance / route.distance : 0,
                end: CLLocation(latitude: end.latitude, longitude: end.longitude),
                endRadiusMeters: HudConstants.navStepAdvanceMeters, ride: nil
            )
        }
        self.init(
            points: DirectionsService.coordinates(of: route.polyline), steps: steps,
            distanceMeters: route.distance, seconds: route.expectedTravelTime, canReroute: true
        )
    }

    var rides: [RideInfo] { steps.compactMap(\.ride) }
}

/// One way to get there, as listed for the user.
struct RouteChoice {
    enum Kind { case walk, train, bus, mixed }
    let kind: Kind
    let route: NavRoute
    let minutes: Int
    /// "¥180" from NAVITIME, nil when unknown (or walking).
    let fare: String?
}

/// The list shown after "I want to go to X", and Neo's pick (an index into choices).
struct TripChoices {
    let destinationName: String
    let choices: [RouteChoice]
    let recommended: Int
    /// Why no train / bus is listed ("Add a RapidAPI key...", "NAVITIME: ..."); nil when they're there.
    let transitNote: String?
}

// MARK: - What the Nav tab shows

struct NavProgress {
    let destinationName: String
    let remainingMeters: Double
    let remainingMinutes: Int
    /// Whole route length, for the progress bar.
    let totalMeters: Double
    /// The next turn, and how far away it is. nil when only the arrival is left.
    let nextTurn: String?
    let metersToNextTurn: Double
    /// The turn after that, for a heads-up.
    let turnAfter: String?
    /// Direction to the next turn point relative to where the phone points,
    /// degrees clockwise (0 = straight ahead). nil without the compass.
    let relativeBearing: Double?
    let rerouting: Bool
    /// The train / bus the user is on right now (current step is a ride).
    let ride: RideInfo?
}

struct PlaceInfo {
    let name: String
    let walkingMeters: Double
    let walkingMinutes: Int
}

enum NavState {
    case idle
    case finding(String)
    case choosing(TripChoices)
    case active(NavProgress)
    case place(PlaceInfo)
    case arrived(String)
    case failed(String)
}

/// What the map shows: `center` drawn at `anchorYFraction` of the height
/// (horizontally centered), with `radiusMeters` from there to the side edge.
struct MapFrame {
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let anchorYFraction: CGFloat

    var metersPerPixel: Double { radiusMeters / (Double(HudConstants.navMapWidthPx) / 2) }

    /// Middle and reach that show all `points` plus a margin (the map is half
    /// as tall as wide, so north-south distance counts double).
    static func fit(_ points: [CLLocationCoordinate2D]) -> (center: CLLocationCoordinate2D, radiusMeters: Double)? {
        guard let first = points.first else { return nil }
        var south = first.latitude, north = first.latitude, west = first.longitude, east = first.longitude
        for point in points {
            south = min(south, point.latitude); north = max(north, point.latitude)
            west = min(west, point.longitude); east = max(east, point.longitude)
        }
        let middle = CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        let eastWest = CLLocation(latitude: middle.latitude, longitude: west)
            .distance(from: CLLocation(latitude: middle.latitude, longitude: east)) / 2
        let northSouth = CLLocation(latitude: south, longitude: middle.longitude)
            .distance(from: CLLocation(latitude: north, longitude: middle.longitude)) / 2
        let radius = max(eastWest, northSouth * 2) * HudConstants.navPlaceFitMargin
        return (middle, max(radius, HudConstants.navZoomMinMeters))
    }
}

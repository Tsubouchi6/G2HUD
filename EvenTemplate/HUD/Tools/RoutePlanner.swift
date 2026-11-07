// RoutePlanner.swift
//
// "I want to go to X" without saying how: lists the ways to get there
// (walking from Apple Maps, train / bus / mixed from NAVITIME via TransitService)
// and picks one to recommend:
//   walk when it's short (navWalkAlwaysMinutes), or not much slower than the
//   fastest ride (navWalkExtraMinutes) and still reasonable (navWalkMaxMinutes);
//   otherwise the fastest ride, the cheaper / fewer-transfer one on a near tie.
// When trains / buses can't be fetched (no key, not subscribed, quota used up,
// no network) it lists walking with the reason (TripChoices.transitNote), so
// it never looks like walking is simply the best way.
//
// Public API:
//   RoutePlanner(directions:transit:)
//   choices(to:from:name:transitOnly:) async throws -> TripChoices
//   static kind(of route:) -> RouteChoice.Kind

import CoreLocation
import Foundation
import MapKit

@MainActor
final class RoutePlanner {

    private let directions: DirectionsService
    private let transit: TransitService

    init(directions: DirectionsService, transit: TransitService) {
        self.directions = directions
        self.transit = transit
    }

    /// All the ways to `place` (at most navMaxChoices), with `recommended` set.
    /// transitOnly: the user asked for the train / bus, so walking isn't listed.
    func choices(to place: MKMapItem, from here: CLLocation, name: String, transitOnly: Bool) async throws -> TripChoices {
        async let walkRoute = try? await directions.route(to: place, mode: .walking)
        async let transitResult = fetchRides(from: here.coordinate, to: place.placemark.coordinate)
        let (rides, transitNote) = await transitResult

        var list: [RouteChoice] = []
        if !transitOnly, let walk = await walkRoute {
            let route = NavRoute(apple: walk)
            list.append(RouteChoice(kind: .walk, route: route, minutes: Self.minutes(route.seconds), fare: nil))
        }
        for ride in rides where !ride.route.rides.isEmpty {
            list.append(RouteChoice(kind: Self.kind(of: ride.route), route: ride.route,
                                    minutes: Self.minutes(ride.route.seconds), fare: ride.fare))
        }
        if list.isEmpty {
            // Nothing at all: say why trains / buses failed, if they did.
            if let transitNote { throw TransitError(errorDescription: transitNote) }
            if transitOnly { throw TransitError.noRoute }
            throw DirectionsError.noRoute
        }
        list = Array(list.prefix(HudConstants.navMaxChoices))
        return TripChoices(destinationName: name, choices: list, recommended: Self.recommend(list), transitNote: transitNote)
    }

    /// Train / bus routes, or none plus the reason (never silently empty).
    private func fetchRides(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async
        -> ([(route: NavRoute, fare: String?)], String?) {
        do {
            let routes = try await transit.routes(from: origin, to: destination)
            return routes.contains { !$0.route.rides.isEmpty } ? (routes, nil) : (routes, HudText.t(.navNoTransit))
        } catch {
            return ([], error.localizedDescription)
        }
    }

    // MARK: - Picking

    private static func recommend(_ list: [RouteChoice]) -> Int {
        let rides = list.indices.filter { list[$0].kind != .walk }
        guard let fastestRide = rides.min(by: { list[$0].minutes < list[$1].minutes }) else { return 0 }
        if let walk = list.firstIndex(where: { $0.kind == .walk }) {
            let walkMinutes = list[walk].minutes
            if walkMinutes <= HudConstants.navWalkAlwaysMinutes { return walk }
            if walkMinutes <= HudConstants.navWalkMaxMinutes,
               walkMinutes <= list[fastestRide].minutes + HudConstants.navWalkExtraMinutes { return walk }
        }
        // Near tie with the fastest ride: fewer transfers wins.
        let nearTie = rides.filter { list[$0].minutes <= list[fastestRide].minutes + HudConstants.navTieMinutes }
        return nearTie.min { list[$0].route.rides.count < list[$1].route.rides.count } ?? fastestRide
    }

    static func kind(of route: NavRoute) -> RouteChoice.Kind {
        let rides = route.rides
        if rides.isEmpty { return .walk }
        if rides.allSatisfy(\.isBus) { return .bus }
        if rides.contains(where: \.isBus) { return .mixed }
        return .train
    }

    private static func minutes(_ seconds: Double) -> Int {
        max(Int((seconds / 60).rounded(.up)), 1)
    }
}

// Navigator.swift
//
// Follows a route as the user moves: which step they're on, distance to the
// next turn, distance and time left, re-routing when off the route, arrival.
// Step i's instruction describes the turn at the START of step i, so the
// "next turn" is step i+1's instruction, reached at the end of step i.
//
// Public API:
//   Navigator(location:directions:)
//   @Published state: NavState
//   @Published minimal: Bool                 // one line at the top, nothing else
//   start(destination:mode:minimal:)         // finds the nearest match, routes, follows
//   stop()
//   showMap()                                // route picture on the lens again
//   onMapPicture: ((Data, String) -> Void)?  // HudController shows it on the lens
//   onArrived: ((String) -> Void)?
//   enum NavState, struct NavProgress

import CoreLocation
import Foundation
import MapKit

struct NavProgress {
    let destinationName: String
    let remainingMeters: Double
    let remainingMinutes: Int
    /// The next turn, and how far away it is. nil when only the arrival is left.
    let nextTurn: String?
    let metersToNextTurn: Double
    /// The turn after that, for a heads-up.
    let turnAfter: String?
    let rerouting: Bool
}

enum NavState {
    case idle
    case finding(String)
    case active(NavProgress)
    case arrived(String)
    case failed(String)
}

@MainActor
final class Navigator: ObservableObject {

    // MARK: - State

    @Published private(set) var state: NavState = .idle
    @Published var minimal = false

    var onMapPicture: ((Data, String) -> Void)?
    var onArrived: ((String) -> Void)?

    private let location: LocationService
    private let directions: DirectionsService

    private var destination: MKMapItem?
    private var destinationName = ""
    private var mode: DirectionsMode = .walking
    private var route: MKRoute?
    private var steps: [MKRoute.Step] = []
    private var stepEnds: [CLLocation] = []
    private var routePoints: [CLLocation] = []
    private var stepIndex = 0
    private var lastLocation: CLLocation?
    private var lastRerouteAt = Date.distantPast
    private var isRerouting = false

    init(location: LocationService, directions: DirectionsService) {
        self.location = location
        self.directions = directions
    }

    // MARK: - Control

    func start(destination query: String, mode: DirectionsMode, minimal: Bool) {
        stop()
        self.mode = mode
        self.minimal = minimal
        state = .finding(query)
        Task {
            do {
                let here = try await location.currentLocation()
                let place = try await directions.nearestPlace(query, near: here)
                destination = place
                destinationName = place.name ?? query
                try await loadRoute(from: here)
                if !minimal { await sendMapPicture() }
                location.startUpdates { [weak self] update in self?.follow(update) }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        location.stopUpdates()
        route = nil
        destination = nil
        state = .idle
    }

    func showMap() {
        Task { await sendMapPicture() }
    }

    // MARK: - Route

    private func loadRoute(from here: CLLocation) async throws {
        guard let destination else { return }
        let route = try await directions.route(to: destination, mode: mode)
        self.route = route
        steps = route.steps
        stepEnds = steps.map { step in
            let end = DirectionsService.coordinates(of: step.polyline).last ?? step.polyline.coordinate
            return CLLocation(latitude: end.latitude, longitude: end.longitude)
        }
        routePoints = DirectionsService.coordinates(of: route.polyline).map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        stepIndex = 0
        lastLocation = here
        publishProgress(at: here)
    }

    private func sendMapPicture() async {
        guard let route, let here = lastLocation,
              let png = await directions.mapPicture(route: route, user: here.coordinate)
        else { return }
        onMapPicture?(png, destinationName)
    }

    // MARK: - Following

    private func follow(_ here: CLLocation) {
        guard route != nil, let destination else { return }
        lastLocation = here

        let target = destination.placemark.coordinate
        if here.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) <= HudConstants.navArrivalMeters {
            location.stopUpdates()
            state = .arrived(destinationName)
            onArrived?(destinationName)
            return
        }

        // Advance past every step end we've reached.
        while stepIndex < stepEnds.count - 1,
              here.distance(from: stepEnds[stepIndex]) <= HudConstants.navStepAdvanceMeters {
            stepIndex += 1
        }

        if isOffRoute(here) { reroute(from: here) }
        publishProgress(at: here)
    }

    private func isOffRoute(_ here: CLLocation) -> Bool {
        guard let nearest = routePoints.map({ here.distance(from: $0) }).min() else { return false }
        return nearest > HudConstants.navOffRouteMeters + max(here.horizontalAccuracy, 0)
    }

    private func reroute(from here: CLLocation) {
        guard !isRerouting, Date().timeIntervalSince(lastRerouteAt) >= HudConstants.navRerouteMinSeconds else { return }
        isRerouting = true
        lastRerouteAt = Date()
        Task {
            try? await loadRoute(from: here)
            isRerouting = false
            publishProgress(at: lastLocation ?? here)
        }
    }

    private func publishProgress(at here: CLLocation) {
        guard let route, !steps.isEmpty else { return }
        let toStepEnd = here.distance(from: stepEnds[stepIndex])
        let laterSteps = steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        let remaining = toStepEnd + laterSteps
        let minutes = route.distance > 0 ? Int((route.expectedTravelTime * remaining / route.distance / 60).rounded(.up)) : 0

        let upcoming = steps.dropFirst(stepIndex + 1).filter { !$0.instructions.isEmpty }
        state = .active(NavProgress(
            destinationName: destinationName,
            remainingMeters: remaining,
            remainingMinutes: max(minutes, 1),
            nextTurn: upcoming.first?.instructions,
            metersToNextTurn: toStepEnd,
            turnAfter: upcoming.dropFirst().first?.instructions,
            rerouting: isRerouting
        ))
    }
}

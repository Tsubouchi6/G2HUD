// Navigator.swift
//
// Follows a route as the user moves: which step they're on, distance to the
// next turn, distance and time left, re-routing when off the route, arrival.
// Step i's instruction describes the turn at the START of step i, so the
// "next turn" is step i+1's instruction, reached at the end of step i.
//
// Public API:
//   Navigator(location:directions:heading:useCompass:)
//     useCompass: true while the glasses aren't connected — then the phone's
//     compass turns the arrow and the mini-map (phone held like a map).
//   @Published state: NavState
//   @Published minimal: Bool                 // one line at the top, nothing else
//   @Published miniMap: Data?                // G2-style mini-map PNG (MiniMapRenderer)
//   start(destination:mode:minimal:)         // finds the nearest match, routes, follows
//   stop()
//   showMap()                                // back to the full view with the mini-map
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
    /// Direction to the next turn point relative to where the phone points,
    /// degrees clockwise (0 = straight ahead). nil without the compass.
    let relativeBearing: Double?
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
    @Published private(set) var miniMap: Data?

    var onArrived: ((String) -> Void)?

    private let location: LocationService
    private let directions: DirectionsService
    private let heading: HeadingService
    private let useCompass: () -> Bool
    private var headingDegrees: Double?

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
    private var miniMapDrawnAt = Date.distantPast
    /// Streets around `streetsCenter` (OpenStreetMap), refetched after moving away.
    private var streets: [Street] = []
    private var streetsCenter: CLLocation?
    private var streetsBlockedUntil = Date.distantPast
    private var isFetchingStreets = false

    init(location: LocationService, directions: DirectionsService, heading: HeadingService, useCompass: @escaping () -> Bool) {
        self.location = location
        self.directions = directions
        self.heading = heading
        self.useCompass = useCompass
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
                location.startUpdates { [weak self] update in self?.follow(update) }
                heading.start { [weak self] degrees in self?.turned(to: degrees) }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        location.stopUpdates()
        heading.stop()
        headingDegrees = nil
        route = nil
        destination = nil
        miniMap = nil
        streets = []
        streetsCenter = nil
        state = .idle
    }

    func showMap() {
        minimal = false
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
        miniMapDrawnAt = .distantPast  // new route: draw it right away
        lastLocation = here
        publishProgress(at: here)
    }

    // MARK: - Following

    private func follow(_ here: CLLocation) {
        guard route != nil, let destination else { return }
        lastLocation = here

        let target = destination.placemark.coordinate
        if here.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) <= HudConstants.navArrivalMeters {
            location.stopUpdates()
            heading.stop()
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

    /// Phone compass moved: redraw the arrow.
    private func turned(to degrees: Double) {
        headingDegrees = degrees
        if let here = lastLocation, case .active = state { publishProgress(at: here) }
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

    /// Redraws the mini-map at most every navMiniMapRefreshSeconds (each new
    /// picture takes the glasses 0.5-2 s to receive).
    private func drawMiniMap(at here: CLLocation) {
        guard Date().timeIntervalSince(miniMapDrawnAt) >= HudConstants.navMiniMapRefreshSeconds,
              let destination
        else { return }
        miniMapDrawnAt = Date()
        fetchStreetsIfNeeded(around: here)
        miniMap = MiniMapRenderer.png(
            route: routePoints.map(\.coordinate),
            streets: streets,
            user: here.coordinate,
            nextTurn: stepIndex < stepEnds.count - 1 ? stepEnds[stepIndex].coordinate : nil,
            destination: destination.placemark.coordinate,
            headingDegrees: useCompass() ? headingDegrees : nil
        )
    }

    /// Gets streets for the mini-map when there are none yet or the user has
    /// moved streetsRefetchMeters from where they were fetched (Overpass policy:
    /// cache, few requests, back off after 429/406). Redraws when they arrive.
    private func fetchStreetsIfNeeded(around here: CLLocation) {
        if let center = streetsCenter, here.distance(from: center) < HudConstants.streetsRefetchMeters { return }
        guard !isFetchingStreets, Date() >= streetsBlockedUntil else { return }
        isFetchingStreets = true
        Task {
            do {
                streets = try await StreetMapClient.streets(
                    around: here.coordinate, radiusMeters: HudConstants.streetsFetchRadiusMeters
                )
                streetsCenter = here
                miniMapDrawnAt = .distantPast
                if let latest = lastLocation { drawMiniMap(at: latest) }
            } catch {
                streetsBlockedUntil = Date().addingTimeInterval(HudConstants.overpassRetrySeconds)
            }
            isFetchingStreets = false
        }
    }

    private func publishProgress(at here: CLLocation) {
        guard let route, !steps.isEmpty else { return }
        let toStepEnd = here.distance(from: stepEnds[stepIndex])
        let laterSteps = steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        let remaining = toStepEnd + laterSteps
        let minutes = route.distance > 0 ? Int((route.expectedTravelTime * remaining / route.distance / 60).rounded(.up)) : 0

        let upcoming = steps.dropFirst(stepIndex + 1).filter { !$0.instructions.isEmpty }
        var relative: Double?
        if useCompass(), let headingDegrees {
            let bearing = HeadingService.bearing(from: here.coordinate, to: stepEnds[stepIndex].coordinate)
            relative = (bearing - headingDegrees + 360).truncatingRemainder(dividingBy: 360)
        }
        drawMiniMap(at: here)
        state = .active(NavProgress(
            destinationName: destinationName,
            remainingMeters: remaining,
            remainingMinutes: max(minutes, 1),
            nextTurn: upcoming.first?.instructions,
            metersToNextTurn: toStepEnd,
            turnAfter: upcoming.dropFirst().first?.instructions,
            relativeBearing: relative,
            rerouting: isRerouting
        ))
    }
}

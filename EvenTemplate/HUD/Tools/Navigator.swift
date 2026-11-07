// Navigator.swift
//
// The Nav tab's brain, in three modes:
//   directions — follows a route as the user moves: which step they're on,
//                distance to the next turn, distance and time left, re-routing
//                when off a walk/drive route, arrival. The map is centered on the user.
//                Train/bus routes (NAVITIME) are followed the same way: a ride is
//                one step from station to station.
//   choosing   — "I want to go to X": the ways to get there (RoutePlanner) with
//                Neo's pick, until the user chooses one (choose(_:)).
//   place      — "where is the nearest X": the user and X both fit on the map,
//                with the walking route between them; no turn-by-turn.
// Zoom in/out halves/doubles the map's reach: around the user in directions,
// around the place in place mode (zoom out from there widens again).
// Data types (NavRoute, NavState, ...) are in NavModels.swift.
//
// Public API:
//   Navigator(location:directions:planner:heading:useCompass:)
//     useCompass: true while the glasses aren't connected — then the phone's
//     compass turns the arrows (phone held like a map).
//   @Published state: NavState
//   @Published minimal: Bool                 // one line at the top, nothing else
//   @Published miniMap: Data?                // map PNG, 400x200 (MiniMapRenderer)
//   @Published mapStatus: String             // phone-only: whether the Apple Maps background loaded
//   start(destination:match:mode:) -> Task   // walking/driving: directions to the nearest match;
//                                            // transit: the best train/bus way; choose: list the ways
//   showPlace(_ query:, match:) -> Task      // where the nearest match is, with the user
//   goToShownPlace(mode:) -> Task?           // "take me there": the place on the map (no new
//                                            // search, so it's the same place); nil if none
//     (each Task ends with nil when found, or the error text)
//   choose(_ number:) -> Bool                // pick a listed way (1-based; 0 = Neo's pick)
//   summaryForAI: String?                    // what the Nav tab shows, for the AIs' context line
//   zoom(in:)                                // halve / double the map's reach; zooming out
//                                            // slides toward the path ahead
//   zoomToOverview()                         // the whole remaining path and the user
//   stop()
//   showMap()                                // back to the view with the map
//   onArrived: ((String) -> Void)?
//   onNotice: ((String) -> Void)?            // "Finding..." / failed search while a map is already up

import CoreLocation
import Foundation
import MapKit

/// How the user wants to get there.
enum TripMode: String {
    case walking, driving
    /// By train or bus: Neo's best transit way, started right away.
    case transit
    /// The user didn't say: list walking / train / bus and recommend one.
    case choose
}

@MainActor
final class Navigator: ObservableObject {

    // MARK: - State

    @Published private(set) var state: NavState = .idle
    @Published var minimal = false
    @Published private(set) var miniMap: Data?
    /// Phone-only note on the street background ("Apple Maps" / why it's missing).
    @Published private(set) var mapStatus = ""

    var onArrived: ((String) -> Void)?
    /// Short notices while a map is already up ("Finding...", a failed search),
    /// so a new request never wipes the current map before it succeeds.
    var onNotice: ((String) -> Void)?

    private let location: LocationService
    private let directions: DirectionsService
    private let planner: RoutePlanner
    private let heading: HeadingService
    private let useCompass: () -> Bool
    private var headingDegrees: Double?

    private var isPlaceMode = false
    private var destination: MKMapItem?
    private var destinationName = ""
    /// Apple mode used when re-routing a walk/drive route.
    private var mode: DirectionsMode = .walking
    private var route: NavRoute?
    private var steps: [NavStep] = []
    private var routePoints: [CLLocationCoordinate2D] = []
    private var stepIndex = 0
    private var lastLocation: CLLocation?
    /// Where the user was when the place was found ("Shibuya, Tokyo"), so the AI
    /// can search fares from there. Apple reverse geocoding (free).
    private var startArea: String?
    /// Where the user is now, refreshed every navAreaRefreshMeters while moving.
    private var currentArea: String?
    private var areaLookedUpAt: CLLocation?
    private var lastRerouteAt = Date.distantPast
    private var isRerouting = false
    private var miniMapDrawnAt = Date.distantPast

    /// Map reach: meters from the center to the map's side edge. nil = default
    /// (directions) or fit-both (place). Zoom sets it.
    private var viewRadiusMeters: Double?
    /// Place mode after "zoom in": the map centers on the place instead of fitting both.
    private var focusOnPlace = false
    /// Place mode: the fit-both reach and middle, fixed when the place is found
    /// (recomputing them from every GPS fix changed the zoom slightly each time,
    /// which threw away the street picture and made the map flicker).
    private var placeFit: (center: CLLocationCoordinate2D, radiusMeters: Double)?

    /// Apple Maps street picture, refetched after moving away or zooming.
    private var background: StreetBackground?
    private var isFetchingBackground = false

    init(location: LocationService, directions: DirectionsService, planner: RoutePlanner,
         heading: HeadingService, useCompass: @escaping () -> Bool) {
        self.location = location
        self.directions = directions
        self.planner = planner
        self.heading = heading
        self.useCompass = useCompass
    }

    // MARK: - Control

    /// Directions (always starting with the map), or the list of ways to get there.
    @discardableResult
    func start(destination query: String, match: PlaceMatch, mode: TripMode) -> Task<String?, Never> {
        begin(label: query, placeMode: false, plan: plan(for: mode)) { [directions] here in
            try await directions.nearestPlace(query, match: match, near: here)
        }
    }

    /// "Where is the nearest X": the place and the user both on the map.
    @discardableResult
    func showPlace(_ query: String, match: PlaceMatch) -> Task<String?, Never> {
        begin(label: query, placeMode: true, plan: plan(for: .walking)) { [directions] here in
            try await directions.nearestPlace(query, match: match, near: here)
        }
    }

    /// "Yes, take me there" after showPlace: the same place, not a new search.
    func goToShownPlace(mode: TripMode) -> Task<String?, Never>? {
        guard isPlaceMode, route != nil, let place = destination else { return nil }
        return begin(label: destinationName, placeMode: false, plan: plan(for: mode)) { _ in place }
    }

    /// Starts the chosen way (1-based as listed; 0 = Neo's pick). False if nothing is listed.
    func choose(_ number: Int) -> Bool {
        guard case .choosing(let trip) = state, let here = lastLocation else { return false }
        let index = number == 0 ? trip.recommended : number - 1
        guard trip.choices.indices.contains(index) else { return false }
        mode = .walking
        minimal = false
        startFollowing(trip.choices[index].route, at: here)
        return true
    }

    /// Zoom out "all the way": the whole remaining path and the user (or, after
    /// "where is X", the place and the user).
    func zoomToOverview() {
        guard let here = lastLocation, route != nil else { return }
        minimal = false
        focusOnPlace = false
        viewRadiusMeters = isPlaceMode ? nil : pathFit(from: here)?.radiusMeters
        miniMapDrawnAt = .distantPast
        drawMiniMap(at: here)
    }

    /// "Shibuya, Tokyo" for a location; nil if Apple can't tell.
    private static func area(of location: CLLocation) async -> String? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [mark.subLocality, mark.locality, mark.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// What the AIs are told about the Nav tab (NavBriefing): the place, where the
    /// user is, and the whole plan, so they can guide the user any time.
    var summaryForAI: String? {
        NavBriefing.summary(
            state: state, address: destination?.placemark.title, area: currentArea ?? startArea,
            steps: steps, stepIndex: stepIndex
        )
    }

    func stop() {
        location.stopUpdates()
        heading.stop()
        headingDegrees = nil
        route = nil
        destination = nil
        miniMap = nil
        background = nil
        viewRadiusMeters = nil
        focusOnPlace = false
        placeFit = nil
        currentArea = nil
        areaLookedUpAt = nil
        state = .idle
    }

    func showMap() {
        minimal = false
    }

    /// Halves (in) or doubles (out) the map's reach, within navZoomMin/MaxMeters.
    /// In place mode, zooming in centers on the place.
    func zoom(in zoomIn: Bool) {
        guard let here = lastLocation, route != nil else { return }
        minimal = false
        let current = viewRadiusMeters ?? currentFrame(at: here).radiusMeters
        let next = zoomIn ? current / 2 : current * 2
        viewRadiusMeters = min(max(next, HudConstants.navZoomMinMeters), HudConstants.navZoomMaxMeters)
        if isPlaceMode, zoomIn { focusOnPlace = true }
        miniMapDrawnAt = .distantPast
        drawMiniMap(at: here)
    }

    // MARK: - Planning

    /// What to do once the place is found: follow one route, or list the ways.
    private enum Plan {
        case follow(NavRoute, DirectionsMode)
        case choose(TripChoices)
    }

    private func plan(for mode: TripMode) -> @MainActor (MKMapItem, CLLocation, String) async throws -> Plan {
        switch mode {
        case .walking, .driving:
            let apple: DirectionsMode = mode == .driving ? .driving : .walking
            return { [directions] place, _, _ in
                .follow(NavRoute(apple: try await directions.route(to: place, mode: apple)), apple)
            }
        case .transit, .choose:
            return { [planner] place, here, name in
                let trip = try await planner.choices(to: place, from: here, name: name, transitOnly: mode == .transit)
                // Asked for the train / bus, or truly only one way: just go. If trains / buses
                // failed, show the list anyway, so the reason is seen.
                if mode == .transit || (trip.choices.count == 1 && trip.transitNote == nil) {
                    return .follow(trip.choices[trip.recommended].route, .walking)
                }
                return .choose(trip)
            }
        }
    }

    /// Finds the place first; only then replaces what's on the map. If the
    /// search fails while a map is up, that map stays and a notice is shown.
    /// `find` picks the destination; the task ends with nil, or the error text.
    private func begin(
        label query: String, placeMode: Bool,
        plan: @escaping @MainActor (MKMapItem, CLLocation, String) async throws -> Plan,
        find: @escaping @MainActor (CLLocation) async throws -> MKMapItem
    ) -> Task<String?, Never> {
        let mapIsUp = route != nil
        if mapIsUp { onNotice?(HudText.t(.navFinding, query)) } else { state = .finding(query) }
        return Task {
            do {
                let here = try await location.currentLocation()
                let place = try await find(here)
                let name = place.name ?? query
                let planned = try await plan(place, here, name)
                stop()
                isPlaceMode = placeMode
                minimal = false
                destination = place
                destinationName = name
                lastLocation = here
                startArea = nil
                Task { [weak self] in self?.startArea = await Self.area(of: here) }
                if placeMode { placeFit = MapFrame.fit([here.coordinate, place.placemark.coordinate]) }
                switch planned {
                case .follow(let route, let appleMode):
                    mode = appleMode
                    startFollowing(route, at: here)
                case .choose(let trip):
                    state = .choosing(trip)
                }
                return nil
            } catch {
                if mapIsUp { onNotice?(error.localizedDescription) } else { state = .failed(error.localizedDescription) }
                return error.localizedDescription
            }
        }
    }

    // MARK: - Route

    private func startFollowing(_ route: NavRoute, at here: CLLocation) {
        use(route, at: here)
        location.startUpdates { [weak self] update in self?.follow(update) }
        heading.start { [weak self] degrees in self?.turned(to: degrees) }
    }

    private func loadRoute(from here: CLLocation) async throws {
        guard let destination else { return }
        use(NavRoute(apple: try await directions.route(to: destination, mode: mode)), at: here)
    }

    private func use(_ route: NavRoute, at here: CLLocation) {
        self.route = route
        steps = route.steps
        routePoints = route.points
        stepIndex = 0
        miniMapDrawnAt = .distantPast  // new route: draw it right away
        lastLocation = here
        publishProgress(at: here)
    }

    // MARK: - Following

    private func follow(_ here: CLLocation) {
        guard let route, let destination else { return }
        lastLocation = here
        refreshArea(at: here)

        if !isPlaceMode {
            let target = destination.placemark.coordinate
            if here.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) <= HudConstants.navArrivalMeters {
                location.stopUpdates()
                heading.stop()
                state = .arrived(destinationName)
                onArrived?(destinationName)
                return
            }
            // Jump past the furthest step end reached (GPS can skip steps,
            // e.g. no signal underground until the arrival station).
            if stepIndex < steps.count - 1,
               let reached = (stepIndex ..< steps.count - 1).last(where: {
                   here.distance(from: steps[$0].end) <= steps[$0].endRadiusMeters
               }) {
                stepIndex = reached + 1
            }
            if route.canReroute, isOffRoute(here) { reroute(from: here) }
        }
        publishProgress(at: here)
    }

    /// Looks up "where am I" again after moving navAreaRefreshMeters (for the AI).
    private func refreshArea(at here: CLLocation) {
        if let last = areaLookedUpAt, here.distance(from: last) < HudConstants.navAreaRefreshMeters { return }
        areaLookedUpAt = here
        Task { [weak self] in
            if let area = await Self.area(of: here) { self?.currentArea = area }
        }
    }

    /// Phone compass moved: redraw the arrow.
    private func turned(to degrees: Double) {
        headingDegrees = degrees
        guard let here = lastLocation else { return }
        switch state {
        case .active, .place: publishProgress(at: here)
        default: break
        }
    }

    private func isOffRoute(_ here: CLLocation) -> Bool {
        let nearest = routePoints.map { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }.min()
        guard let nearest else { return false }
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

    // MARK: - Map

    /// What the map shows: its center, its reach, and where the center sits.
    /// Directions: around the user; zooming out slides the middle toward the
    /// rest of the path (you zoom out to see more of the path, not more of
    /// where you are), reaching "the whole path" at its fit-all reach.
    private func currentFrame(at here: CLLocation) -> MapFrame {
        let near = HudConstants.navMiniMapRadiusMeters
        guard isPlaceMode, let target = destination?.placemark.coordinate else {
            let radius = viewRadiusMeters ?? near
            guard radius > near, let fit = pathFit(from: here) else {
                return MapFrame(center: here.coordinate, radiusMeters: radius,
                                anchorYFraction: HudConstants.navMiniMapUserYFraction)
            }
            return MapFrame(center: Self.slide(from: here.coordinate, toward: fit.center, radius: radius),
                            radiusMeters: radius, anchorYFraction: 0.5)
        }
        if focusOnPlace {
            return MapFrame(center: target, radiusMeters: viewRadiusMeters ?? near, anchorYFraction: 0.5)
        }
        let fit = placeFit ?? MapFrame.fit([here.coordinate, target])
        return MapFrame(center: fit?.center ?? target, radiusMeters: viewRadiusMeters ?? fit?.radiusMeters ?? near,
                        anchorYFraction: 0.5)
    }

    /// Middle of a zoomed-out map: moved from the user toward the middle of the
    /// path ahead, but only as far as keeps the user on the map with a
    /// navUserEdgeMargin share of the half-width / half-height to spare. (Moving
    /// by a fixed share of the way cut the user off: the map is half as tall as
    /// wide, so a path heading north left the frame's reach in a few steps.)
    private static func slide(from user: CLLocationCoordinate2D, toward goal: CLLocationCoordinate2D,
                              radius: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(user.latitude * .pi / 180)
        let east = (goal.longitude - user.longitude) * metersPerDegreeLon
        let north = (goal.latitude - user.latitude) * metersPerDegreeLat
        let keep = 1 - HudConstants.navUserEdgeMargin
        let maxEast = radius * keep           // half-width in meters
        let maxNorth = radius / 2 * keep      // half-height (400x200 map)
        var scale = 1.0
        if abs(east) > maxEast { scale = min(scale, maxEast / abs(east)) }
        if abs(north) > maxNorth { scale = min(scale, maxNorth / abs(north)) }
        return CLLocationCoordinate2D(latitude: user.latitude + north * scale / metersPerDegreeLat,
                                      longitude: user.longitude + east * scale / metersPerDegreeLon)
    }

    /// Fit for the user plus the path still ahead (from the route point nearest
    /// the user to the destination).
    private func pathFit(from here: CLLocation) -> (center: CLLocationCoordinate2D, radiusMeters: Double)? {
        let distances = routePoints.map { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
        let nearest = distances.indices.min { distances[$0] < distances[$1] } ?? 0
        var points = [here.coordinate] + routePoints.dropFirst(nearest)
        if let target = destination?.placemark.coordinate { points.append(target) }
        return MapFrame.fit(points)
    }

    /// Redraws the map at most every navMiniMapRefreshSeconds (each new picture
    /// takes the glasses 0.5-2 s to receive).
    private func drawMiniMap(at here: CLLocation) {
        guard Date().timeIntervalSince(miniMapDrawnAt) >= HudConstants.navMiniMapRefreshSeconds,
              let destination
        else { return }
        let frame = currentFrame(at: here)
        fetchBackgroundIfNeeded(for: frame)
        // Zoom changed and the new street picture isn't here yet: keep the old map
        // up instead of flashing a streetless one (it redraws when the picture lands).
        if let background, !background.matches(frame), miniMap != nil, isFetchingBackground { return }
        miniMapDrawnAt = Date()
        miniMap = MiniMapRenderer.png(
            background: background?.matches(frame) == true ? background : nil,
            frame: frame,
            route: routePoints,
            user: here.coordinate,
            nextTurn: !isPlaceMode && stepIndex < steps.count - 1 ? steps[stepIndex].end.coordinate : nil,
            destination: destination.placemark.coordinate,
            headingDegrees: useCompass() ? headingDegrees : nil
        )
    }

    /// Gets the Apple Maps street picture when there is none for this zoom yet,
    /// or the map center has moved too far from its middle. Redraws when it arrives.
    private func fetchBackgroundIfNeeded(for frame: MapFrame) {
        if let background, background.covers(frame) { return }
        guard !isFetchingBackground else { return }
        isFetchingBackground = true
        Task {
            if let fresh = await StreetBackground.make(for: frame, route: routePoints) {
                background = fresh
                mapStatus = "Apple Maps"
                miniMapDrawnAt = .distantPast
                if let latest = lastLocation { drawMiniMap(at: latest) }
            } else {
                mapStatus = "Apple Maps streets didn't load (route only)"
            }
            isFetchingBackground = false
        }
    }


    private func publishProgress(at here: CLLocation) {
        guard let route, !steps.isEmpty else { return }
        drawMiniMap(at: here)

        if isPlaceMode {
            state = .place(PlaceInfo(
                name: destinationName,
                walkingMeters: route.distanceMeters,
                walkingMinutes: max(Int((route.seconds / 60).rounded(.up)), 1)
            ))
            return
        }

        let step = steps[stepIndex]
        let toStepEnd = here.distance(from: step.end)
        let later = steps.dropFirst(stepIndex + 1)
        let remaining = toStepEnd + later.reduce(0) { $0 + $1.distanceMeters }
        // Time left: the unfinished part of this step plus the later steps.
        let stepShare = step.distanceMeters > 0 ? min(toStepEnd / step.distanceMeters, 1) : 0
        let seconds = step.seconds * stepShare + later.reduce(0) { $0 + $1.seconds }

        let upcoming = later.filter { !$0.instruction.isEmpty }
        var relative: Double?
        if useCompass(), let headingDegrees {
            let bearing = HeadingService.bearing(from: here.coordinate, to: step.end.coordinate)
            relative = (bearing - headingDegrees + 360).truncatingRemainder(dividingBy: 360)
        }
        state = .active(NavProgress(
            destinationName: destinationName,
            remainingMeters: remaining,
            remainingMinutes: max(Int((seconds / 60).rounded(.up)), 1),
            totalMeters: route.distanceMeters,
            nextTurn: upcoming.first?.instruction,
            metersToNextTurn: toStepEnd,
            turnAfter: upcoming.dropFirst().first?.instruction,
            relativeBearing: relative,
            rerouting: isRerouting,
            ride: step.ride
        ))
    }
}

// Navigator.swift
//
// The Nav tab's brain, in two modes:
//   directions — follows a route as the user moves: which step they're on,
//                distance to the next turn, distance and time left, re-routing
//                when off the route, arrival. The map is centered on the user.
//   place      — "where is the nearest X": the user and X both fit on the map,
//                with the walking route between them; no turn-by-turn.
// Zoom in/out halves/doubles the map's reach: around the user in directions,
// around the place in place mode (zoom out from there widens again).
// Step i's instruction describes the turn at the START of step i, so the
// "next turn" is step i+1's instruction, reached at the end of step i.
//
// Public API:
//   Navigator(location:directions:heading:useCompass:)
//     useCompass: true while the glasses aren't connected — then the phone's
//     compass turns the arrows (phone held like a map).
//   @Published state: NavState
//   @Published minimal: Bool                 // one line at the top, nothing else
//   @Published miniMap: Data?                // map PNG, 400x200 (MiniMapRenderer)
//   @Published mapStatus: String             // phone-only: whether the Apple Maps background loaded
//   start(destination:match:mode:) -> Task   // directions to the nearest match (map view)
//   showPlace(_ query:, match:) -> Task      // where the nearest match is, with the user
//   goToShownPlace(mode:) -> Task?           // "take me there": directions to the place on the map
//                                            // (no new search, so it's the same place); nil if none
//     (each Task ends with nil when found, or the error text)
//   summaryForAI: String?                    // what the Nav tab shows, for the AIs' context line
//   zoom(in:)                                // halve / double the map's reach
//   stop()
//   showMap()                                // back to the view with the map
//   onArrived: ((String) -> Void)?
//   onNotice: ((String) -> Void)?            // "Finding..." / failed search while a map is already up
//   enum NavState, struct NavProgress, struct PlaceInfo

import CoreLocation
import Foundation
import MapKit

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
}

struct PlaceInfo {
    let name: String
    let walkingMeters: Double
    let walkingMinutes: Int
}

enum NavState {
    case idle
    case finding(String)
    case active(NavProgress)
    case place(PlaceInfo)
    case arrived(String)
    case failed(String)
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
    private let heading: HeadingService
    private let useCompass: () -> Bool
    private var headingDegrees: Double?

    private var isPlaceMode = false
    private var destination: MKMapItem?
    private var destinationName = ""
    private var mode: DirectionsMode = .walking
    private var route: MKRoute?
    private var steps: [MKRoute.Step] = []
    private var stepEnds: [CLLocation] = []
    private var routePoints: [CLLocation] = []
    private var stepIndex = 0
    private var lastLocation: CLLocation?
    /// Where the user was when the place was found ("Shibuya, Tokyo"), so the AI
    /// can search fares from there. Apple reverse geocoding (free).
    private var startArea: String?
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

    init(location: LocationService, directions: DirectionsService, heading: HeadingService, useCompass: @escaping () -> Bool) {
        self.location = location
        self.directions = directions
        self.heading = heading
        self.useCompass = useCompass
    }

    // MARK: - Control

    /// Directions; always starts with the map (the one-line view only when asked).
    @discardableResult
    func start(destination query: String, match: PlaceMatch, mode: DirectionsMode) -> Task<String?, Never> {
        begin(label: query, mode: mode, placeMode: false) { [directions] here in
            try await directions.nearestPlace(query, match: match, near: here)
        }
    }

    /// "Where is the nearest X": the place and the user both on the map.
    @discardableResult
    func showPlace(_ query: String, match: PlaceMatch) -> Task<String?, Never> {
        begin(label: query, mode: .walking, placeMode: true) { [directions] here in
            try await directions.nearestPlace(query, match: match, near: here)
        }
    }

    /// "Yes, take me there" after showPlace: the same place, not a new search.
    func goToShownPlace(mode: DirectionsMode) -> Task<String?, Never>? {
        guard isPlaceMode, route != nil, let place = destination else { return nil }
        return begin(label: destinationName, mode: mode, placeMode: false) { _ in place }
    }

    /// "Shibuya, Tokyo" for a location; nil if Apple can't tell.
    private static func area(of location: CLLocation) async -> String? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [mark.subLocality, mark.locality, mark.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// One sentence for the AIs about what the Nav tab shows, so follow-ups
    /// ("go there", "how far", "how much to get there") use the real place.
    var summaryForAI: String? {
        let address = destination?.placemark.title.map { " (\($0))" } ?? ""
        let from = startArea.map { ", from the user's area \($0)" } ?? ""
        switch state {
        case .place(let place):
            return "The Nav map shows \(place.name)\(address), \(Int(place.walkingMeters)) m away\(from), "
                + "about \(place.walkingMinutes) min on foot; not navigating there yet"
        case .active(let progress):
            return "Navigating (\(mode.rawValue)) to \(progress.destinationName)\(address)\(from), "
                + "\(Int(progress.remainingMeters)) m and about \(progress.remainingMinutes) min left"
        case .finding(let query):
            return "Searching the map for \(query)"
        default:
            return nil
        }
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

    /// Finds the place first; only then replaces what's on the map. If the
    /// search fails while a map is up, that map stays and a notice is shown.
    /// `find` picks the destination; the task ends with nil, or the error text.
    private func begin(
        label query: String, mode: DirectionsMode, placeMode: Bool,
        find: @escaping @MainActor (CLLocation) async throws -> MKMapItem
    ) -> Task<String?, Never> {
        let mapIsUp = route != nil
        if mapIsUp { onNotice?(HudText.t(.navFinding, query)) } else { state = .finding(query) }
        return Task {
            do {
                let here = try await location.currentLocation()
                let place = try await find(here)
                let route = try await directions.route(to: place, mode: mode)
                stop()
                self.mode = mode
                isPlaceMode = placeMode
                minimal = false
                destination = place
                destinationName = place.name ?? query
                startArea = nil
                Task { [weak self] in self?.startArea = await Self.area(of: here) }
                if placeMode { placeFit = Self.fit(user: here.coordinate, place: place.placemark.coordinate) }
                use(route, at: here)
                location.startUpdates { [weak self] update in self?.follow(update) }
                heading.start { [weak self] degrees in self?.turned(to: degrees) }
                return nil
            } catch {
                if mapIsUp { onNotice?(error.localizedDescription) } else { state = .failed(error.localizedDescription) }
                return error.localizedDescription
            }
        }
    }

    // MARK: - Route

    private func loadRoute(from here: CLLocation) async throws {
        guard let destination else { return }
        use(try await directions.route(to: destination, mode: mode), at: here)
    }

    private func use(_ route: MKRoute, at here: CLLocation) {
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

        if !isPlaceMode {
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
        }
        publishProgress(at: here)
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

    // MARK: - Map

    /// What the map shows: its center, its reach, and where the center sits.
    private func currentFrame(at here: CLLocation) -> MapFrame {
        guard isPlaceMode, let target = destination?.placemark.coordinate else {
            return MapFrame(
                center: here.coordinate,
                radiusMeters: viewRadiusMeters ?? HudConstants.navMiniMapRadiusMeters,
                anchorYFraction: HudConstants.navMiniMapUserYFraction
            )
        }
        if focusOnPlace {
            return MapFrame(center: target, radiusMeters: viewRadiusMeters ?? HudConstants.navMiniMapRadiusMeters, anchorYFraction: 0.5)
        }
        let fit = placeFit ?? Self.fit(user: here.coordinate, place: target)
        return MapFrame(center: fit.center, radiusMeters: viewRadiusMeters ?? fit.radiusMeters, anchorYFraction: 0.5)
    }

    /// Middle and reach that show both points plus a margin (the map is half
    /// as tall as wide, so north-south distance counts double).
    private static func fit(user: CLLocationCoordinate2D, place: CLLocationCoordinate2D) -> (center: CLLocationCoordinate2D, radiusMeters: Double) {
        let middle = CLLocationCoordinate2D(latitude: (user.latitude + place.latitude) / 2,
                                            longitude: (user.longitude + place.longitude) / 2)
        let eastWest = CLLocation(latitude: middle.latitude, longitude: user.longitude)
            .distance(from: CLLocation(latitude: middle.latitude, longitude: place.longitude)) / 2
        let northSouth = CLLocation(latitude: user.latitude, longitude: middle.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: middle.longitude)) / 2
        let radius = max(eastWest, northSouth * 2) * HudConstants.navPlaceFitMargin
        return (middle, max(radius, HudConstants.navZoomMinMeters))
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
            route: routePoints.map(\.coordinate),
            user: here.coordinate,
            nextTurn: !isPlaceMode && stepIndex < stepEnds.count - 1 ? stepEnds[stepIndex].coordinate : nil,
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
            if let fresh = await StreetBackground.make(for: frame, route: routePoints.map(\.coordinate)) {
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
                walkingMeters: route.distance,
                walkingMinutes: max(Int((route.expectedTravelTime / 60).rounded(.up)), 1)
            ))
            return
        }

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
        state = .active(NavProgress(
            destinationName: destinationName,
            remainingMeters: remaining,
            remainingMinutes: max(minutes, 1),
            totalMeters: route.distance,
            nextTurn: upcoming.first?.instructions,
            metersToNextTurn: toStepEnd,
            turnAfter: upcoming.dropFirst().first?.instructions,
            relativeBearing: relative,
            rerouting: isRerouting
        ))
    }
}

/// What the map shows: `center` drawn at `anchorYFraction` of the height
/// (horizontally centered), with `radiusMeters` from there to the side edge.
struct MapFrame {
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let anchorYFraction: CGFloat

    var metersPerPixel: Double { radiusMeters / (Double(HudConstants.navMapWidthPx) / 2) }
}

// DirectionsService.swift
//
// Apple MapKit (free in native apps, no key): finds the nearest place matching
// what the user said ("コンビニ", "Tokyo Station"), and gets a walking or
// driving route with turn-by-turn steps. (The mini-map is MiniMapRenderer.)
// Step instructions come from Apple in the phone's own language.
// What counts as a match is decided by Apple's most relevant result, because
// MapKit also returns loosely related places (a "Wendy's" search also lists
// McDonald's; "pet shop" also lists supermarkets), and the nearest of those
// is often the wrong kind.
//
// Public API:
//   DirectionsService()
//   nearestPlace(_ query:, match:, near:) async throws -> MKMapItem
//   route(to:mode:) async throws -> MKRoute
//   static coordinates(of: MKPolyline) -> [CLLocationCoordinate2D]
//   enum DirectionsMode: walking / driving, enum PlaceMatch, enum DirectionsError

import MapKit

enum DirectionsMode: String {
    case walking, driving
}

/// How the AI says the user named the place.
enum PlaceMatch: String {
    /// A kind of place ("pet shop", "convenience store"): nearest of the same kind.
    case kind
    /// A chain ("Wendy's", "Starbucks"): nearest branch of that chain.
    case brand
    /// One specific place or address ("Tokyo Station"): that place.
    case exact
}

enum DirectionsError: LocalizedError {
    case placeNotFound(String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .placeNotFound(let query): return "Couldn't find \(query) nearby"
        case .noRoute: return "No route found"
        }
    }
}

@MainActor
final class DirectionsService {

    // MARK: - Search

    /// The closest place matching `query`. Apple's most relevant result (no
    /// area limit) decides what a match is (its category, or its chain name);
    /// then a small area is searched first and widened (navSearchRadiiMeters)
    /// until a match turns up. Falls back to that most relevant result.
    func nearestPlace(_ query: String, match: PlaceMatch, near location: CLLocation) async throws -> MKMapItem {
        let maxRadius = HudConstants.navSearchRadiiMeters.last ?? 5000
        let relevant = (try? await search(query, around: location, radius: maxRadius, required: false)) ?? []
        guard let best = relevant.first else { throw DirectionsError.placeNotFound(query) }
        if match == .exact { return best }

        for radius in HudConstants.navSearchRadiiMeters {
            let nearby = (try? await search(query, around: location, radius: radius, required: true)) ?? []
            let nearest = (nearby + relevant)
                .filter { Self.isSame(match, $0, as: best) && distance($0, location) <= radius }
                .min { distance($0, location) < distance($1, location) }
            if let nearest { return nearest }
        }
        return best
    }

    /// One MapKit search. `required` keeps results inside the area (regionPriority).
    private func search(_ query: String, around location: CLLocation, radius: Double, required: Bool) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2
        )
        request.regionPriority = required ? .required : .default
        request.resultTypes = [.pointOfInterest, .address]
        return try await MKLocalSearch(request: request).start().mapItems
    }

    /// kind: same Apple category as the best result. brand: same chain name
    /// (names start alike, "マクドナルド 渋谷店" / "マクドナルド 原宿店").
    private static func isSame(_ match: PlaceMatch, _ item: MKMapItem, as best: MKMapItem) -> Bool {
        let sameCategory = item.pointOfInterestCategory == best.pointOfInterestCategory
        switch match {
        case .exact:
            return item == best
        case .kind:
            return best.pointOfInterestCategory == nil ? item == best : sameCategory
        case .brand:
            let a = nameKey(item), b = nameKey(best)
            let shared = zip(a, b).prefix { $0 == $1 }.count
            return shared >= min(HudConstants.navBrandPrefixChars, b.count)
                && (sameCategory || item.pointOfInterestCategory == nil || best.pointOfInterestCategory == nil)
        }
    }

    /// Name without case, width, spaces or punctuation, for comparing chain names.
    private static func nameKey(_ item: MKMapItem) -> [Character] {
        let folded = (item.name ?? "").folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: nil)
        return Array(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    private func distance(_ item: MKMapItem, _ location: CLLocation) -> CLLocationDistance {
        let coordinate = item.placemark.coordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: location)
    }

    // MARK: - Route

    /// Route from the phone's current location.
    func route(to destination: MKMapItem, mode: DirectionsMode) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = mode == .walking ? .walking : .automobile
        guard let route = try await MKDirections(request: request).calculate().routes.first else {
            throw DirectionsError.noRoute
        }
        return route
    }

    // MARK: - Helpers

    static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }
}

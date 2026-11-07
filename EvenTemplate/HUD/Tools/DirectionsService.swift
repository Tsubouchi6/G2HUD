// DirectionsService.swift
//
// Apple MapKit (free in native apps, no key): finds the nearest place matching
// what the user said ("コンビニ", "Tokyo Station"), and gets a walking or
// driving route with turn-by-turn steps. (The mini-map is MiniMapRenderer.)
// Step instructions come from Apple in the phone's own language.
//
// Public API:
//   DirectionsService()
//   nearestPlace(_ query:, near:) async throws -> MKMapItem
//   route(to:mode:) async throws -> MKRoute
//   static coordinates(of: MKPolyline) -> [CLLocationCoordinate2D]
//   enum DirectionsMode: walking / driving, enum DirectionsError

import MapKit

enum DirectionsMode: String {
    case walking, driving
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

    /// The closest result for `query` around `location`. Searches a small area
    /// first and widens it (navSearchRadiiMeters) only if nothing is found;
    /// results outside the area are not allowed (regionPriority .required).
    func nearestPlace(_ query: String, near location: CLLocation) async throws -> MKMapItem {
        for radius in HudConstants.navSearchRadiiMeters {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2
            )
            request.regionPriority = .required
            request.resultTypes = [.pointOfInterest, .address]
            guard let items = try? await MKLocalSearch(request: request).start().mapItems else { continue }
            if let nearest = items.min(by: { distance($0, location) < distance($1, location) }),
               distance(nearest, location) <= radius * 1.5 {
                return nearest
            }
        }
        throw DirectionsError.placeNotFound(query)
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

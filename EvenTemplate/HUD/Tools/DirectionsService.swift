// DirectionsService.swift
//
// Apple MapKit (free in native apps, no key): finds the nearest place matching
// what the user said ("コンビニ", "Tokyo Station"), gets a walking or driving
// route with turn-by-turn steps, and draws a route map picture for the lens.
// Step instructions come from Apple in the phone's own language.
//
// Public API:
//   DirectionsService()
//   nearestPlace(_ query:, near:) async throws -> MKMapItem
//   route(to:mode:) async throws -> MKRoute
//   mapPicture(route:user:) async -> Data?         // 400x200 PNG, dark map + white route
//   static coordinates(of: MKPolyline) -> [CLLocationCoordinate2D]
//   enum DirectionsMode: walking / driving, enum DirectionsError

import MapKit
import UIKit

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

    /// The closest result for `query` around `location`.
    func nearestPlace(_ query: String, near location: CLLocation) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: HudConstants.navSearchRadiusMeters * 2,
            longitudinalMeters: HudConstants.navSearchRadiusMeters * 2
        )
        request.resultTypes = [.pointOfInterest, .address]
        let items = try await MKLocalSearch(request: request).start().mapItems
        let nearest = items.min { distance($0, location) < distance($1, location) }
        guard let nearest else { throw DirectionsError.placeNotFound(query) }
        return nearest
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

    // MARK: - Map picture

    /// Dark map of the whole route with the route in thick white, the user as
    /// a dot and the destination as a ring. Sized for the lens picture area.
    func mapPicture(route: MKRoute, user: CLLocationCoordinate2D) async -> Data? {
        let size = CGSize(
            width: HudConstants.imageTileWidthPx * HudConstants.imageTilesAcross,
            height: HudConstants.imageTileHeightPx * HudConstants.imageTilesDown
        )
        let options = MKMapSnapshotter.Options()
        options.mapRect = Self.paddedRect(route.polyline.boundingMapRect, aspect: size.width / size.height)
        options.size = size
        options.scale = 1
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let coordinates = Self.coordinates(of: route.polyline)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(HudConstants.navMapRouteWidthPx)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            for (index, coordinate) in coordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                if index == 0 { cg.move(to: point) } else { cg.addLine(to: point) }
            }
            cg.strokePath()

            let dot = HudConstants.navMapMarkerRadiusPx
            let userPoint = snapshot.point(for: user)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: userPoint.x - dot, y: userPoint.y - dot, width: dot * 2, height: dot * 2))
            if let end = coordinates.last {
                let endPoint = snapshot.point(for: end)
                cg.setLineWidth(3)
                cg.strokeEllipse(in: CGRect(x: endPoint.x - dot * 1.5, y: endPoint.y - dot * 1.5, width: dot * 3, height: dot * 3))
            }
        }
        return image.pngData()
    }

    /// Route bounds plus a margin, widened or heightened to the picture's aspect.
    private static func paddedRect(_ rect: MKMapRect, aspect: CGFloat) -> MKMapRect {
        var padded = rect.insetBy(dx: -rect.width * 0.15 - 100, dy: -rect.height * 0.15 - 100)
        if padded.width / padded.height < aspect {
            let width = padded.height * aspect
            padded = padded.insetBy(dx: -(width - padded.width) / 2, dy: 0)
        } else {
            let height = padded.width / aspect
            padded = padded.insetBy(dx: 0, dy: -(height - padded.height) / 2)
        }
        return padded
    }

    // MARK: - Helpers

    static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }
}

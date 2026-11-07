// MiniMapRenderer.swift
//
// Draws the navigation map (400x200, the biggest picture the glasses take),
// in the style of the G2's own Navigate mini map: a game-style map around the user that turns with the direction
// they face (heading-up): nearby streets as thin lines (OpenStreetMap), the
// route thick on top, the next turn point, the destination ring, and the
// user's arrow. White on black (black
// is see-through on the lens). Without a heading it is drawn north-up and
// the arrow shows the direction of travel instead.
//
// Projection: local equirectangular around the user (fine over a few hundred
// meters): x = Δλ·cos φ0·R, y = Δφ·R. Source: movable-type.co.uk/scripts/latlong.html
// ("Equirectangular approximation").
//
// Public API:
//   MiniMapRenderer.png(route:streets:user:nextTurn:destination:headingDegrees:) -> Data?

import CoreLocation
import UIKit

enum MiniMapRenderer {

    /// Earth radius in meters (mean). Source: movable-type.co.uk.
    private static let earthRadiusMeters = 6_371_000.0

    static func png(
        route: [CLLocationCoordinate2D],
        streets: [Street],
        user: CLLocationCoordinate2D,
        nextTurn: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D,
        headingDegrees: Double?
    ) -> Data? {
        let size = CGSize(width: HudConstants.navMapWidthPx, height: HudConstants.navMapHeightPx)
        // User a bit below center, so more of the way ahead is visible.
        let center = CGPoint(x: size.width / 2, y: size.height * HudConstants.navMiniMapUserYFraction)
        let pixelsPerMeter = (size.width / 2) / HudConstants.navMiniMapRadiusMeters
        let rotation = (headingDegrees ?? 0) * .pi / 180

        /// Meters east/north of the user, rotated so the facing direction is up, to pixels.
        func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            let φ0 = user.latitude * .pi / 180
            let east = (coordinate.longitude - user.longitude) * .pi / 180 * cos(φ0) * earthRadiusMeters
            let north = (coordinate.latitude - user.latitude) * .pi / 180 * earthRadiusMeters
            let x = east * cos(rotation) - north * sin(rotation)
            let y = east * sin(rotation) + north * cos(rotation)
            return CGPoint(x: center.x + x * pixelsPerMeter, y: center.y - y * pixelsPerMeter)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Streets: thin and dimmer, so the route stands out on top.
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            for street in streets {
                cg.setStrokeColor(UIColor.white.withAlphaComponent(street.isMajor ? 0.75 : 0.5).cgColor)
                cg.setLineWidth(street.isMajor ? HudConstants.navMapMajorStreetWidthPx : HudConstants.navMapMinorStreetWidthPx)
                for (index, coordinate) in street.points.enumerated() {
                    let p = point(coordinate)
                    if index == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
                }
                cg.strokePath()
            }

            // Route
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(HudConstants.navMapRouteWidthPx)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            for (index, coordinate) in route.enumerated() {
                let p = point(coordinate)
                if index == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
            }
            cg.strokePath()

            // Next turn: filled dot. Destination: ring.
            let marker = HudConstants.navMapMarkerRadiusPx
            cg.setFillColor(UIColor.white.cgColor)
            if let nextTurn {
                let p = point(nextTurn)
                cg.fillEllipse(in: CGRect(x: p.x - marker, y: p.y - marker, width: marker * 2, height: marker * 2))
            }
            let end = point(destination)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: end.x - marker * 1.6, y: end.y - marker * 1.6, width: marker * 3.2, height: marker * 3.2))

            // User arrow: points up when heading-up; north-up maps point it along the route start.
            var arrowAngle = 0.0
            if headingDegrees == nil, let ahead = route.first(where: { point($0).distance(to: center) > 10 }) {
                let p = point(ahead)
                arrowAngle = atan2(p.x - center.x, center.y - p.y)
            }
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: arrowAngle)
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: 0, y: -14))
            arrow.addLine(to: CGPoint(x: 10, y: 10))
            arrow.addLine(to: CGPoint(x: 0, y: 4))
            arrow.addLine(to: CGPoint(x: -10, y: 10))
            arrow.closeSubpath()
            cg.addPath(arrow)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillPath()
            cg.restoreGState()
        }
        return image.pngData()
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

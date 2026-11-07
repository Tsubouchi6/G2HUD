// MiniMapRenderer.swift
//
// Draws the navigation map (400x200, the biggest picture the glasses take):
// Apple Maps streets behind (StreetBackground, north-up, like the G2's
// "Full Map" mode), the route thick on top, the next turn as a dot, the
// destination as a ring, and the user's arrow in the middle. The arrow turns
// with the phone's compass (no glasses), else it points along the route.
// White on black: black is see-through on the lens.
//
// Without a background yet (still loading, or no network) it draws the route
// alone with a local equirectangular projection: x = Δλ·cos φ0·R, y = Δφ·R
// (fine over a few hundred meters). Source: movable-type.co.uk/scripts/latlong.html
//
// Public API:
//   MiniMapRenderer.png(background:route:user:nextTurn:destination:headingDegrees:) -> Data?

import CoreLocation
import UIKit

enum MiniMapRenderer {

    /// Earth radius in meters (mean). Source: movable-type.co.uk.
    private static let earthRadiusMeters = 6_371_000.0

    static func png(
        background: StreetBackground?,
        route: [CLLocationCoordinate2D],
        user: CLLocationCoordinate2D,
        nextTurn: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D,
        headingDegrees: Double?
    ) -> Data? {
        let size = CGSize(width: HudConstants.navMapWidthPx, height: HudConstants.navMapHeightPx)
        // User a bit below center, so more of the way ahead is visible.
        let center = CGPoint(x: size.width / 2, y: size.height * HudConstants.navMiniMapUserYFraction)

        /// Coordinate to a pixel on this map, with the user at `center`.
        let point: (CLLocationCoordinate2D) -> CGPoint
        if let background {
            let userInBackground = background.point(for: user)
            point = { coordinate in
                let p = background.point(for: coordinate)
                return CGPoint(x: p.x - userInBackground.x + center.x, y: p.y - userInBackground.y + center.y)
            }
        } else {
            let pixelsPerMeter = (size.width / 2) / HudConstants.navMiniMapRadiusMeters
            let φ0 = user.latitude * .pi / 180
            point = { coordinate in
                let east = (coordinate.longitude - user.longitude) * .pi / 180 * cos(φ0) * earthRadiusMeters
                let north = (coordinate.latitude - user.latitude) * .pi / 180 * earthRadiusMeters
                return CGPoint(x: center.x + east * pixelsPerMeter, y: center.y - north * pixelsPerMeter)
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Streets (Apple Maps), shifted so the user sits at `center`.
            if let background {
                let userInBackground = background.point(for: user)
                background.image.draw(at: CGPoint(x: center.x - userInBackground.x, y: center.y - userInBackground.y))
            }

            // Route: a black outline first so it stays readable over streets.
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            for (color, width) in [(UIColor.black, HudConstants.navMapRouteWidthPx + 4), (UIColor.white, HudConstants.navMapRouteWidthPx)] {
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(width)
                for (index, coordinate) in route.enumerated() {
                    let p = point(coordinate)
                    if index == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
                }
                cg.strokePath()
            }

            // Next turn: filled dot. Destination: ring.
            let marker = HudConstants.navMapMarkerRadiusPx
            cg.setFillColor(UIColor.white.cgColor)
            if let nextTurn {
                let p = point(nextTurn)
                cg.fillEllipse(in: CGRect(x: p.x - marker, y: p.y - marker, width: marker * 2, height: marker * 2))
            }
            let end = point(destination)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: end.x - marker * 1.6, y: end.y - marker * 1.6, width: marker * 3.2, height: marker * 3.2))

            // User arrow (map is north-up): phone compass, else along the route ahead.
            var arrowAngle = (headingDegrees ?? 0) * .pi / 180
            if headingDegrees == nil, let ahead = route.first(where: { hypot(point($0).x - center.x, point($0).y - center.y) > 10 }) {
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
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(3)
            cg.setFillColor(UIColor.white.cgColor)
            cg.drawPath(using: .fillStroke)
            cg.restoreGState()
        }
        return image.pngData()
    }
}

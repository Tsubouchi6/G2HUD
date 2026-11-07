// StreetBackground.swift
//
// Apple Maps street picture behind the navigation map (MKMapSnapshotter, free
// in native apps). Apple doesn't hand apps street shapes, only rendered map
// pictures, so this is a street-level snapshot: dark style, muted, no points
// of interest, no 3D buildings. It is north-up (turning it would turn its
// labels upside-down) and navBackgroundScale times the map's size at the map's
// zoom, so it can be reused while the user walks; Navigator fetches a new one
// after the map center moves away from its middle, or after zooming.
//
// Cleaning: roads must light up and the land around them go black (only
// black is see-through on the lens). Which one is brighter depends on Apple's
// style (in the dark style the land blocks came out brighter than the roads),
// so it is measured instead of assumed: the route always runs on roads, so the
// gray under the route is the road color, and the most common gray is the land.
// Each pixel is lit by how far it is from the land color: roads come out at
// navBackgroundRoadBrightness, street names (even further from land) brighter.
// Rendered at 2x and drawn at 1x, so edges and text shrink smoothly.
//
// Public API:
//   StreetBackground.make(for frame:, route:) async -> StreetBackground?
//   image: UIImage, center: CLLocation, metersPerPixel: Double
//   point(for coordinate) -> CGPoint      // pixel in `image`
//   matches(frame) -> Bool                // same zoom (usable for drawing)
//   covers(frame) -> Bool                 // same zoom and still near enough (no refetch needed)

import CoreLocation
import MapKit
import UIKit

struct StreetBackground {

    let image: UIImage
    let center: CLLocation
    let metersPerPixel: Double
    private let snapshot: MKMapSnapshotter.Snapshot

    func matches(_ frame: MapFrame) -> Bool {
        abs(frame.metersPerPixel - metersPerPixel) / metersPerPixel < 0.01
    }

    /// Refetch distance grows with the zoom (navBackgroundRefetchMeters at the default zoom).
    func covers(_ frame: MapFrame) -> Bool {
        let defaultMetersPerPixel = HudConstants.navMiniMapRadiusMeters / (Double(HudConstants.navMapWidthPx) / 2)
        let limit = HudConstants.navBackgroundRefetchMeters * metersPerPixel / defaultMetersPerPixel
        let target = CLLocation(latitude: frame.center.latitude, longitude: frame.center.longitude)
        return matches(frame) && target.distance(from: center) < limit
    }

    /// Where a coordinate falls in `image`, in pixels.
    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        snapshot.point(for: coordinate)
    }

    /// Snapshot of navBackgroundScale x the map size around the frame's center,
    /// at the frame's zoom.
    @MainActor
    static func make(for frame: MapFrame, route: [CLLocationCoordinate2D]) async -> StreetBackground? {
        let scale = HudConstants.navBackgroundScale
        let size = CGSize(width: CGFloat(HudConstants.navMapWidthPx) * scale,
                          height: CGFloat(HudConstants.navMapHeightPx) * scale)
        let center = CLLocation(latitude: frame.center.latitude, longitude: frame.center.longitude)
        let metersPerPixel = frame.metersPerPixel
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(center.coordinate.latitude)
        let width = Double(size.width) * metersPerPixel * pointsPerMeter
        let height = Double(size.height) * metersPerPixel * pointsPerMeter
        let middle = MKMapPoint(center.coordinate)

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false

        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(x: middle.x - width / 2, y: middle.y - height / 2, width: width, height: height)
        options.size = size
        options.scale = HudConstants.navBackgroundRenderScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let image = cleanStreets(snapshot, route: route)
        else { return nil }
        return StreetBackground(image: image, center: center, metersPerPixel: metersPerPixel, snapshot: snapshot)
    }

    /// Lights each pixel by its distance from the land gray (see header).
    /// Returned at the snapshot's scale (2x), so drawing it at its point size
    /// into the 1x map shrinks it smoothly.
    private static func cleanStreets(_ snapshot: MKMapSnapshotter.Snapshot, route: [CLLocationCoordinate2D]) -> UIImage? {
        guard let source = snapshot.image.cgImage else { return nil }
        let width = source.width, height = source.height
        var gray = [UInt8](repeating: 0, count: width * height)
        // The buffer must stay valid while drawing, so draw inside its pointer scope.
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Land = most common gray (median); road = median gray under the route.
        let land = median(gray)
        let scale = snapshot.image.scale
        var underRoute: [UInt8] = []
        for coordinate in route {
            let p = snapshot.point(for: coordinate)
            let x = Int(p.x * scale), y = Int(p.y * scale)
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            underRoute.append(gray[y * width + x])
        }
        // Too few route points on this picture: assume roads are the lightest 10%.
        let road = underRoute.count >= HudConstants.navBackgroundMinRouteSamples
            ? median(underRoute)
            : gray.sorted()[gray.count * 9 / 10]
        let roadDistance = max(abs(Double(road) - Double(land)), HudConstants.navBackgroundMinContrast)
        let roadLevel = Double(HudConstants.navBackgroundRoadBrightness)

        var lit = [UInt8](repeating: 0, count: width * height)
        for index in 0 ..< gray.count {
            let distance = abs(Double(gray[index]) - Double(land))
            lit[index] = UInt8(min(1, distance / roadDistance * roadLevel) * 255)
        }

        guard let provider = CGDataProvider(data: Data(lit) as CFData),
              let output = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: output, scale: scale, orientation: .up)
    }

    private static func median(_ values: [UInt8]) -> UInt8 {
        // Counting sort: 256 buckets, fast for millions of pixels.
        var counts = [Int](repeating: 0, count: 256)
        for value in values { counts[Int(value)] += 1 }
        var seen = 0
        for (value, count) in counts.enumerated() {
            seen += count
            if seen * 2 >= values.count { return UInt8(value) }
        }
        return 0
    }
}

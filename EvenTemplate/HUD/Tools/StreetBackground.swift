// StreetBackground.swift
//
// Apple Maps street picture behind the navigation map (MKMapSnapshotter, free
// in native apps). Apple doesn't hand apps street shapes, only rendered map
// pictures, so this is a street-level snapshot: dark style, muted, no points
// of interest, no 3D buildings. It is north-up (turning it would turn its
// labels upside-down) and twice the map's size, so it can be reused while the
// user walks; Navigator fetches a new one after they move away from its center.
//
// The dark style's background is dark grey, which would glow faintly on the
// lens (only black is see-through), so a tone curve pushes it to black and
// keeps the lighter roads and labels.
//
// Public API:
//   StreetBackground.make(around:) async -> StreetBackground?
//   image: UIImage, center: CLLocation
//   point(for coordinate) -> CGPoint      // pixel in `image`

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreLocation
import MapKit
import UIKit

struct StreetBackground {

    let image: UIImage
    let center: CLLocation
    private let snapshot: MKMapSnapshotter.Snapshot

    /// Where a coordinate falls in `image`, in pixels.
    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        snapshot.point(for: coordinate)
    }

    /// Snapshot of navBackgroundScale x the map size around `center`, at the
    /// map's scale (1 px per meter for a 200 m radius on 400 px).
    @MainActor
    static func make(around center: CLLocation) async -> StreetBackground? {
        let scale = HudConstants.navBackgroundScale
        let size = CGSize(width: CGFloat(HudConstants.navMapWidthPx) * scale,
                          height: CGFloat(HudConstants.navMapHeightPx) * scale)
        let metersPerPixel = HudConstants.navMiniMapRadiusMeters / (Double(HudConstants.navMapWidthPx) / 2)
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
        options.scale = 1
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let image = blackenBackground(snapshot.image)
        else { return nil }
        return StreetBackground(image: image, center: center, snapshot: snapshot)
    }

    /// Grayscale, then a tone curve: the dark map background goes to black
    /// (see-through on the lens), roads and labels stay lit.
    private static func blackenBackground(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let gray = CIFilter.colorControls()
        gray.inputImage = input
        gray.saturation = 0
        let curve = CIFilter.toneCurve()
        curve.inputImage = gray.outputImage
        curve.point0 = CGPoint(x: 0, y: 0)
        curve.point1 = CGPoint(x: HudConstants.navBackgroundBlackLevel, y: 0)
        curve.point2 = CGPoint(x: 0.45, y: 0.55)
        curve.point3 = CGPoint(x: 0.7, y: 0.85)
        curve.point4 = CGPoint(x: 1, y: 1)
        let context = CIContext()
        guard let output = curve.outputImage,
              let cgImage = context.createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

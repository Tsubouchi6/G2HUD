// StreetBackground.swift
//
// Apple Maps street picture behind the navigation map (MKMapSnapshotter, free
// in native apps). Apple doesn't hand apps street shapes, only rendered map
// pictures, so this is a street-level snapshot: dark style, muted, no points
// of interest, no 3D buildings. It is north-up (turning it would turn its
// labels upside-down) and twice the map's size, so it can be reused while the
// user walks; Navigator fetches a new one after they move away from its center.
//
// Cleaning (Core Image), done at 2x resolution so edges come out smooth when
// shrunk: grayscale -> threshold (roads white, the dark grey background black,
// since only black is see-through on the lens) -> "opening" erases thin label
// text and specks -> "closing" fills the holes street-name labels cut into
// roads -> dim to one even road brightness, so the route stands out on top.
// (Morphological opening/closing: erode+dilate / dilate+erode; CIMorphology filters.)
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
        options.scale = HudConstants.navBackgroundRenderScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let image = cleanStreets(snapshot.image)
        else { return nil }
        return StreetBackground(image: image, center: center, snapshot: snapshot)
    }

    /// Roads only, as one even dim gray on black, with label holes filled.
    /// Returned at the snapshot's 2x scale, so drawing it at its point size
    /// into the 1x map shrinks it smoothly.
    private static func cleanStreets(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let gray = CIFilter.colorControls()
        gray.inputImage = input
        gray.saturation = 0

        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = gray.outputImage
        threshold.threshold = Float(HudConstants.navBackgroundRoadThreshold)

        // Opening: erode then dilate, removes bright strokes thinner than 2x the radius (text, specks).
        let erodeText = CIFilter.morphologyMinimum()
        erodeText.inputImage = threshold.outputImage
        erodeText.radius = Float(HudConstants.navBackgroundTextRadiusPx)
        let restoreRoads = CIFilter.morphologyMaximum()
        restoreRoads.inputImage = erodeText.outputImage
        restoreRoads.radius = Float(HudConstants.navBackgroundTextRadiusPx)

        // Closing: dilate then erode, fills dark gaps narrower than 2x the radius (label holes).
        let fillHoles = CIFilter.morphologyMaximum()
        fillHoles.inputImage = restoreRoads.outputImage
        fillHoles.radius = Float(HudConstants.navBackgroundHoleRadiusPx)
        let restoreEdges = CIFilter.morphologyMinimum()
        restoreEdges.inputImage = fillHoles.outputImage
        restoreEdges.radius = Float(HudConstants.navBackgroundHoleRadiusPx)

        // Dim: roads at one even level, below the route's full white.
        let dim = CIFilter.colorMatrix()
        dim.inputImage = restoreEdges.outputImage
        let level = HudConstants.navBackgroundRoadBrightness
        dim.rVector = CIVector(x: level, y: 0, z: 0, w: 0)
        dim.gVector = CIVector(x: 0, y: level, z: 0, w: 0)
        dim.bVector = CIVector(x: 0, y: 0, z: level, w: 0)

        guard let output = dim.outputImage,
              let cgImage = CIContext().createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}

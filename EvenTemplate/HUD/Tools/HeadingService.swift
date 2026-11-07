// HeadingService.swift
//
// The phone's compass heading (which way its top edge points), for the
// directions arrow while testing without glasses. Core Location heading
// updates; true north when available, else magnetic.
//
// Public API:
//   HeadingService()
//   start(_ onHeading: (Double) -> Void) / stop()      // degrees clockwise from north
//   static bearing(from:to:) -> Double                  // degrees clockwise from north

import CoreLocation
import Foundation

@MainActor
final class HeadingService: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var onHeading: ((Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = HudConstants.navHeadingFilterDegrees
        manager.headingOrientation = .portrait
    }

    func start(_ onHeading: @escaping (Double) -> Void) {
        guard CLLocationManager.headingAvailable() else { return }
        self.onHeading = onHeading
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        onHeading = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.onHeading?(degrees) }
    }

    /// Initial great-circle bearing from `from` to `to`, 0-360° clockwise from north.
    /// θ = atan2(sin Δλ · cos φ2, cos φ1 · sin φ2 − sin φ1 · cos φ2 · cos Δλ)
    /// Source: movable-type.co.uk/scripts/latlong.html (Chris Veness).
    nonisolated static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let φ1 = from.latitude * .pi / 180, φ2 = to.latitude * .pi / 180
        let Δλ = (to.longitude - from.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

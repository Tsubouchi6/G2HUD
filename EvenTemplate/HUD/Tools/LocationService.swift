// LocationService.swift
//
// The phone's location for directions, using Core Location's async updates
// (CLLocationUpdate.liveUpdates, iOS 17+). CLServiceSession asks for "while
// using" permission; CLBackgroundActivitySession keeps updates coming while the
// phone is locked during navigation (needs the "location" background mode).
//
// Public API:
//   LocationService()
//   currentLocation() async throws -> CLLocation        // one good fix
//   startUpdates(_ onUpdate:) / stopUpdates()           // continuous, for navigation
//   enum LocationError: denied / unavailable

import CoreLocation
import Foundation

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "Location is off for G2HUD (Settings > Privacy > Location Services)"
        case .unavailable: return "Location unavailable"
        }
    }
}

@MainActor
final class LocationService {

    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?

    // MARK: - One fix

    /// First location accurate to `navFirstFixAccuracyMeters`, or the best one
    /// seen once `navFirstFixTimeoutSeconds` have passed.
    func currentLocation() async throws -> CLLocation {
        ensureAuthorizationSession()
        let started = Date()
        var best: CLLocation?
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw LocationError.denied }
            guard let location = update.location, location.horizontalAccuracy >= 0 else { continue }
            if best == nil || location.horizontalAccuracy < best!.horizontalAccuracy { best = location }
            if location.horizontalAccuracy <= HudConstants.navFirstFixAccuracyMeters { return location }
            if Date().timeIntervalSince(started) > HudConstants.navFirstFixTimeoutSeconds, let best { return best }
        }
        throw LocationError.unavailable
    }

    // MARK: - Continuous

    func startUpdates(_ onUpdate: @escaping @MainActor (CLLocation) -> Void) {
        stopUpdates()
        ensureAuthorizationSession()
        backgroundSession = CLBackgroundActivitySession()
        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    if Task.isCancelled { break }
                    if let location = update.location, location.horizontalAccuracy >= 0 { onUpdate(location) }
                }
            } catch {
                // Updates ended (e.g. permission removed); navigation just stops moving.
            }
        }
    }

    func stopUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    // MARK: - Helpers

    private func ensureAuthorizationSession() {
        if serviceSession == nil { serviceSession = CLServiceSession(authorization: .whenInUse) }
    }
}

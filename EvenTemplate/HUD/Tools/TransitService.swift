// TransitService.swift
//
// Train and bus routes from the Google Routes API (computeRoutes, travelMode
// TRANSIT, with alternatives). Apple Maps can't give apps transit steps (only
// an arrival time), so this is the one paid-tier service the Nav tab uses:
// free up to 10,000 requests a month (Compute Routes Essentials), one request
// per "I want to go to X". The key is entered in Settings and stays on the phone.
// Sources: developers.google.com/maps/documentation/routes/transit-route,
// developers.google.com/maps/billing-and-pricing/pricing
//
// Public API:
//   TransitService(settings:)
//   isConfigured: Bool
//   routes(from:to:) async throws -> [(route: NavRoute, fare: String?)]   // up to a few alternatives
//   enum TransitError

import CoreLocation
import Foundation

enum TransitError: LocalizedError {
    case noKey
    case server(String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .noKey: return HudText.t(.navNoGoogleKey)
        case .server(let message): return "Google: \(message)"
        case .noRoute: return HudText.t(.navNoTransit)
        }
    }
}

@MainActor
final class TransitService {

    private let settings: HudSettings

    init(settings: HudSettings) {
        self.settings = settings
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    private var apiKey: String { settings.googleMapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Request

    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws
        -> [(route: NavRoute, fare: String?)] {
        guard isConfigured else { throw TransitError.noKey }
        guard let url = URL(string: HudConstants.googleRoutesEndpoint) else { throw TransitError.noRoute }

        var request = URLRequest(url: url, timeoutInterval: HudConstants.searchTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        // Lets the key be restricted to this app in the Google Cloud console.
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let body: [String: Any] = [
            "origin": Self.waypoint(origin),
            "destination": Self.waypoint(destination),
            "travelMode": "TRANSIT",
            "computeAlternativeRoutes": true,
            "languageCode": settings.language.speechLocaleId,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = json["error"] as? [String: Any] {
            throw TransitError.server(error["message"] as? String ?? "error")
        }
        let routes = (json["routes"] as? [[String: Any]] ?? []).compactMap(Self.parseRoute)
        guard !routes.isEmpty else { throw TransitError.noRoute }
        return routes
    }

    /// Only the fields we read (Google bills and answers by field mask).
    private static let fieldMask = [
        "routes.duration", "routes.distanceMeters", "routes.polyline.encodedPolyline",
        "routes.localizedValues.transitFare",
        "routes.legs.steps.distanceMeters", "routes.legs.steps.staticDuration",
        "routes.legs.steps.polyline.encodedPolyline", "routes.legs.steps.endLocation",
        "routes.legs.steps.navigationInstruction", "routes.legs.steps.travelMode",
        "routes.legs.steps.transitDetails",
    ].joined(separator: ",")

    private static func waypoint(_ coordinate: CLLocationCoordinate2D) -> [String: Any] {
        ["location": ["latLng": ["latitude": coordinate.latitude, "longitude": coordinate.longitude]]]
    }

    // MARK: - Parsing

    private static func parseRoute(_ json: [String: Any]) -> (route: NavRoute, fare: String?)? {
        let legs = json["legs"] as? [[String: Any]] ?? []
        let steps = legs.flatMap { $0["steps"] as? [[String: Any]] ?? [] }.compactMap(parseStep)
        guard !steps.isEmpty else { return nil }
        let polyline = ((json["polyline"] as? [String: Any])?["encodedPolyline"] as? String).map(PolylineDecoder.decode) ?? []
        let fare = ((json["localizedValues"] as? [String: Any])?["transitFare"] as? [String: Any])?["text"] as? String
        let route = NavRoute(
            points: polyline, steps: steps,
            distanceMeters: (json["distanceMeters"] as? NSNumber)?.doubleValue ?? steps.reduce(0) { $0 + $1.distanceMeters },
            seconds: seconds(json["duration"]) ?? steps.reduce(0) { $0 + $1.seconds },
            canReroute: false
        )
        return (route, fare)
    }

    private static func parseStep(_ json: [String: Any]) -> NavStep? {
        guard let end = location(json["endLocation"]) else { return nil }
        let distance = (json["distanceMeters"] as? NSNumber)?.doubleValue ?? 0
        let duration = seconds(json["staticDuration"]) ?? 0
        if let transit = json["transitDetails"] as? [String: Any], let ride = parseRide(transit) {
            return NavStep(
                instruction: HudText.t(.navBoard, rideName(ride), ride.departs ?? ride.fromStop),
                distanceMeters: distance, seconds: duration, end: end,
                endRadiusMeters: HudConstants.navStationRadiusMeters, ride: ride
            )
        }
        let instruction = (json["navigationInstruction"] as? [String: Any])?["instructions"] as? String ?? ""
        return NavStep(
            instruction: instruction, distanceMeters: distance, seconds: duration, end: end,
            endRadiusMeters: HudConstants.navStepAdvanceMeters, ride: nil
        )
    }

    private static func parseRide(_ json: [String: Any]) -> RideInfo? {
        let stops = json["stopDetails"] as? [String: Any] ?? [:]
        let line = json["transitLine"] as? [String: Any] ?? [:]
        let vehicleType = (line["vehicle"] as? [String: Any])?["type"] as? String ?? ""
        let times = json["localizedValues"] as? [String: Any] ?? [:]
        guard let lineName = (line["nameShort"] as? String) ?? (line["name"] as? String) else { return nil }
        return RideInfo(
            isBus: busTypes.contains(vehicleType),
            line: lineName,
            headsign: json["headsign"] as? String,
            fromStop: (stops["departureStop"] as? [String: Any])?["name"] as? String ?? "",
            toStop: (stops["arrivalStop"] as? [String: Any])?["name"] as? String ?? "",
            departs: clock(times["departureTime"]),
            arrives: clock(times["arrivalTime"]),
            stopCount: (json["stopCount"] as? NSNumber)?.intValue ?? 0
        )
    }

    /// Google vehicle types that are buses (the rest are rail of some kind).
    private static let busTypes: Set<String> = ["BUS", "INTERCITY_BUS", "TROLLEYBUS", "SHARE_TAXI"]

    /// "JR Yamanote for Shinjuku"
    static func rideName(_ ride: RideInfo) -> String {
        ride.headsign.map { HudText.t(.navLineToward, ride.line, $0) } ?? ride.line
    }

    /// "1234s" -> 1234
    private static func seconds(_ value: Any?) -> Double? {
        (value as? String).flatMap { Double($0.replacingOccurrences(of: "s", with: "")) }
    }

    private static func location(_ value: Any?) -> CLLocation? {
        guard let latLng = (value as? [String: Any])?["latLng"] as? [String: Any],
              let latitude = (latLng["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (latLng["longitude"] as? NSNumber)?.doubleValue
        else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    /// localizedValues.departureTime -> "06:52"
    private static func clock(_ value: Any?) -> String? {
        ((value as? [String: Any])?["time"] as? [String: Any])?["text"] as? String
    }
}

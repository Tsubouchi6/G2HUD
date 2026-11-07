// TransitService.swift
//
// Train and bus routes from NAVITIME Route (totalnavi) on RapidAPI:
// GET /route_transit?start=lat,lon&goal=lat,lon&start_time=...&shape=true.
// Apple Maps can't give apps transit steps (only an arrival time), and
// NAVITIME is free on RapidAPI's Basic plan: 500 requests a month, a hard
// limit (it stops answering, it never bills). One request per "I want to go
// to X". The key is entered in Settings and stays on the phone.
// Sources: api-sdk.navitime.co.jp/api/specs/api_guide/route_transit.html,
// api-sdk.navitime.co.jp/api/rakutenrapid/ (plans), qiita.com/jagaimo310 (RapidAPI host/headers)
//
// Response, as used here: items[] (one per route) with summary.move {time
// (min), distance (m), fare {unit_N: yen}} and sections[] alternating
// point {name, coord {lat, lon}, gateway (exit)} / move {move: walk | local_train | local_bus ...,
// line_name, from_time, to_time, time, distance, transport {destination, getoff}};
// shapes: GeoJSON FeatureCollection (LineString coordinates are [lon, lat]).
// NAVITIME walking sections have no turn-by-turn, so each is one "walk to X" step.
//
// Public API:
//   TransitService(settings:)
//   isConfigured: Bool
//   routes(from:to:) async throws -> [(route: NavRoute, fare: String?)]   // up to navMaxChoices
//   struct TransitError

import CoreLocation
import Foundation

/// The message is built when thrown (HudText is main-actor), in the HUD language.
struct TransitError: LocalizedError {
    let errorDescription: String?

    @MainActor static var noKey: TransitError { TransitError(errorDescription: HudText.t(.navNoTransitKey)) }
    @MainActor static var noRoute: TransitError { TransitError(errorDescription: HudText.t(.navNoTransit)) }
    static func server(_ message: String) -> TransitError { TransitError(errorDescription: "NAVITIME: \(message)") }
}

@MainActor
final class TransitService {

    private let settings: HudSettings

    init(settings: HudSettings) {
        self.settings = settings
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    private var apiKey: String { settings.transitApiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Request

    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws
        -> [(route: NavRoute, fare: String?)] {
        guard isConfigured else { throw TransitError.noKey }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        var components = URLComponents(string: "https://\(HudConstants.transitApiHost)/route_transit")
        components?.queryItems = [
            URLQueryItem(name: "start", value: Self.point(origin)),
            URLQueryItem(name: "goal", value: Self.point(destination)),
            URLQueryItem(name: "start_time", value: formatter.string(from: Date())),
            URLQueryItem(name: "limit", value: String(HudConstants.navMaxChoices)),
            URLQueryItem(name: "shape", value: "true"),
        ]
        guard let url = components?.url else { throw TransitError.noRoute }

        var request = URLRequest(url: url, timeoutInterval: HudConstants.searchTimeoutSeconds)
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(HudConstants.transitApiHost, forHTTPHeaderField: "x-rapidapi-host")

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // RapidAPI errors: {"message": "..."}; NAVITIME errors: {"error": {"message": ...}} or similar.
            let message = json["message"] as? String
                ?? (json["error"] as? [String: Any])?["message"] as? String
                ?? "HTTP \(status)"
            throw TransitError.server(message)
        }
        let routes = (json["items"] as? [[String: Any]] ?? []).compactMap(Self.parseRoute)
        guard !routes.isEmpty else { throw TransitError.noRoute }
        return routes
    }

    private static func point(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - Parsing

    private static func parseRoute(_ item: [String: Any]) -> (route: NavRoute, fare: String?)? {
        let sections = item["sections"] as? [[String: Any]] ?? []
        var steps: [NavStep] = []
        var trace: [CLLocationCoordinate2D] = []  // point coordinates, if there is no shape
        for (index, section) in sections.enumerated() {
            if section["type"] as? String == "point" {
                if let coordinate = coordinate(section["coord"]) { trace.append(coordinate) }
                continue
            }
            guard section["type"] as? String == "move",
                  let from = sections[safe: index - 1], let to = sections[safe: index + 1],
                  let end = coordinate(to["coord"])
            else { continue }
            if let step = parseMove(section, from: from["name"] as? String ?? "", to: to["name"] as? String ?? "",
                                    gate: to["gateway"] as? String, end: end) {
                steps.append(step)
            }
        }
        guard !steps.isEmpty else { return nil }

        let move = (item["summary"] as? [String: Any])?["move"] as? [String: Any] ?? [:]
        let shape = lineCoordinates(item["shapes"])
        let route = NavRoute(
            points: shape.isEmpty ? trace : shape, steps: steps,
            distanceMeters: number(move["distance"]) ?? steps.reduce(0) { $0 + $1.distanceMeters },
            seconds: (number(move["time"]) ?? 0) * 60,
            canReroute: false
        )
        return (route, fareText(move["fare"]))
    }

    /// `gate`: the arrival point's gateway (station exit) from NAVITIME, if any.
    private static func parseMove(_ section: [String: Any], from: String, to: String, gate: String?,
                                  end: CLLocationCoordinate2D) -> NavStep? {
        let kind = section["move"] as? String ?? ""
        let distance = number(section["distance"]) ?? 0
        let seconds = (number(section["time"]) ?? 0) * 60
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        if kind == "walk" {
            return NavStep(
                instruction: to.isEmpty ? "" : HudText.t(.navWalkTo, to), distanceMeters: distance, seconds: seconds,
                end: endLocation, endRadiusMeters: HudConstants.navStationRadiusMeters, ride: nil
            )
        }
        let transport = section["transport"] as? [String: Any] ?? [:]
        let line = section["line_name"] as? String ?? transport["name"] as? String ?? ""
        let ride = RideInfo(
            isBus: kind.contains("bus"),
            line: line,
            headsign: (transport["destination"] as? String) ?? ((transport["destination"] as? [String: Any])?["name"] as? String),
            fromStop: from,
            toStop: to,
            departs: clock(section["from_time"]),
            arrives: clock(section["to_time"]),
            stopCount: 0,
            exitGate: gate
        )
        return NavStep(
            instruction: HudText.t(.navBoard, rideName(ride), ride.departs ?? from),
            distanceMeters: distance, seconds: seconds, end: endLocation,
            endRadiusMeters: HudConstants.navStationRadiusMeters, ride: ride
        )
    }

    /// "JR Yamanote for Shinjuku"
    static func rideName(_ ride: RideInfo) -> String {
        ride.headsign.map { HudText.t(.navLineToward, ride.line, $0) } ?? ride.line
    }

    /// fare {unit_48: IC fare, unit_0: ticket fare, ...} in yen -> "¥180" (IC when given).
    private static func fareText(_ value: Any?) -> String? {
        guard let fares = value as? [String: Any] else { return nil }
        let yen = number(fares["unit_48"]) ?? number(fares["unit_0"])
        return yen.map { "¥\(Int($0))" }
    }

    /// GeoJSON FeatureCollection -> one list of coordinates ([lon, lat] pairs).
    private static func lineCoordinates(_ value: Any?) -> [CLLocationCoordinate2D] {
        let features = (value as? [String: Any])?["features"] as? [[String: Any]] ?? []
        return features.flatMap { feature -> [CLLocationCoordinate2D] in
            let geometry = feature["geometry"] as? [String: Any] ?? [:]
            let lines: [[Any]]
            switch geometry["type"] as? String {
            case "LineString": lines = [geometry["coordinates"] as? [Any] ?? []]
            case "MultiLineString": lines = geometry["coordinates"] as? [[Any]] ?? []
            default: lines = []
            }
            return lines.flatMap { line in
                line.compactMap { pair -> CLLocationCoordinate2D? in
                    guard let values = pair as? [Any], values.count >= 2,
                          let lon = number(values[0]), let lat = number(values[1]) else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
        }
    }

    private static func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let coord = value as? [String: Any], let lat = number(coord["lat"]), let lon = number(coord["lon"]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }

    /// "2024-01-01T13:00:00+09:00" -> "13:00"
    private static func clock(_ value: Any?) -> String? {
        guard let text = value as? String, let tee = text.firstIndex(of: "T") else { return nil }
        return String(text[text.index(after: tee)...].prefix(5))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

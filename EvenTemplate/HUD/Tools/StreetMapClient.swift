// StreetMapClient.swift
//
// Streets around a point from OpenStreetMap, for the navigation map, via the
// public Overpass API (free, no key), trying each public server in turn. Usage policy: identify the app
// (User-Agent), cache, stay well under 100 queries/day for regular use, and
// wait 30 s after HTTP 429/406. Source: wiki.openstreetmap.org/wiki/Overpass_API
// The caller (Navigator) caches by area, so a walk makes only a few requests.
//
// Public API:
//   StreetMapClient.streets(around:radiusMeters:) async throws -> [Street]
//   struct Street { points, isMajor }

import CoreLocation
import Foundation

struct Street {
    let points: [CLLocationCoordinate2D]
    /// Big roads (motorway ... tertiary) draw thicker than small streets and paths.
    let isMajor: Bool
}

enum StreetMapClient {

    private struct Response: Decodable {
        struct Element: Decodable {
            struct Point: Decodable { let lat: Double; let lon: Double }
            let geometry: [Point]?
            let tags: [String: String]?
        }
        let elements: [Element]
    }

    private static let majorKinds: Set<String> = [
        "motorway", "trunk", "primary", "secondary", "tertiary",
        "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
    ]

    /// Roads people walk or drive on (not buildings, rivers, rails...).
    private static let highwayPattern =
        "^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|pedestrian|footway|path|steps|cycleway|track)(_link)?$"

    static func streets(around center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Street] {
        let query = """
        [out:json][timeout:15];
        way(around:\(Int(radiusMeters)),\(center.latitude),\(center.longitude))[highway~"\(highwayPattern)"];
        out geom;
        """
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)

        // Each public server in turn until one answers.
        var lastError: Error = StreetMapError.http(0)
        for endpoint in HudConstants.overpassEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url, timeoutInterval: HudConstants.overpassTimeoutSeconds)
            request.httpMethod = "POST"
            request.setValue(HudConstants.overpassUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw StreetMapError.http(status) }
                return try decode(data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func decode(_ data: Data) throws -> [Street] {
        try JSONDecoder().decode(Response.self, from: data).elements.compactMap { element in
            guard let geometry = element.geometry, geometry.count >= 2 else { return nil }
            return Street(
                points: geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                isMajor: majorKinds.contains(element.tags?["highway"] ?? "")
            )
        }
    }
}

enum StreetMapError: LocalizedError {
    /// 429 / 406 = too many requests: wait overpassRetrySeconds before asking again.
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "map server error (HTTP \(code))"
        }
    }
}

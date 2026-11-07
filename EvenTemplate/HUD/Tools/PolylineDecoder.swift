// PolylineDecoder.swift
//
// Decodes Google's "encoded polyline" strings (Routes API route and step
// shapes) into coordinates. Algorithm: each value is a signed delta from the
// previous point, ×1e5, zig-zag encoded, split into 5-bit chunks (low first),
// each chunk + 63 as one character, 0x20 set on all but the last chunk.
// Source: developers.google.com/maps/documentation/utilities/polylinealgorithm
//
// Public API: PolylineDecoder.decode(_ encoded:) -> [CLLocationCoordinate2D]

import CoreLocation

enum PolylineDecoder {

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(encoded.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        var points: [CLLocationCoordinate2D] = []

        /// Next zig-zag value, or nil at a malformed end.
        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let chunk = Int(bytes[index]) - 63
                index += 1
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }

        while index < bytes.count {
            guard let deltaLatitude = nextValue(), let deltaLongitude = nextValue() else { break }
            latitude += deltaLatitude
            longitude += deltaLongitude
            points.append(CLLocationCoordinate2D(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
        }
        return points
    }
}

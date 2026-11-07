// WeatherService.swift
//
// Current temperature for the status bar, from Open-Meteo (free, no API key,
// open-meteo.com/en/docs: /v1/forecast?current=temperature_2m). Refreshes
// every weatherRefreshSeconds from the phone's location while the HUD runs.
// Celsius, or Fahrenheit where the phone uses US units.
//
// Public API:
//   WeatherService(location:)
//   start() / stop()
//   latestText: String?        // "14C" / "57F"; nil until the first fetch works

import CoreLocation
import Foundation

@MainActor
final class WeatherService {

    private let location: LocationService
    private var refresher: Task<Void, Never>?
    private(set) var latestText: String?

    init(location: LocationService) {
        self.location = location
    }

    func start() {
        refresher?.cancel()
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(HudConstants.weatherRefreshSeconds))
            }
        }
    }

    func stop() {
        refresher?.cancel()
        refresher = nil
    }

    /// One fetch; keeps the last value when it fails (no network, no location).
    private func refresh() async {
        guard let here = try? await location.currentLocation() else { return }
        let fahrenheit = Locale.current.measurementSystem == .us
        var components = URLComponents(string: HudConstants.weatherEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", here.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", here.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue
        else { return }
        latestText = "\(Int(temperature.rounded()))\(fahrenheit ? "F" : "C")"
    }
}

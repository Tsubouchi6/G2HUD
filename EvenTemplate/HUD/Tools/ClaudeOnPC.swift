// ClaudeOnPC.swift
//
// Asks Claude through the PC bridge (PCBridge/bridge.ps1 running `claude -p`
// on your PC, reached over Tailscale). Uses your Claude plan, no API key.
// Claude may end its reply with one action line the app carries out:
//   IMAGE: <2-5 English words>                       -> web photo on the lens
//   STOCK: <Yahoo name> | <day|week|month|year|fiveYears> -> price chart
//   CHART: <title> | <unit> | <label>=<n>; <label>=<n>    -> bar/line chart
//   SAVE: <short title>                              -> saves this chat (Saved tab)
//   LISTEN: <title> | <ja|en|pt|any> | <HH:mm|now> | <HH:mm|open> -> saves what people say (language, start, stop)
//   LISTEN_STOP                                      -> stops and keeps that text (or cancels a planned one)
//   DIRECTIONS: <place|shown> | <walking|driving> | <kind|brand|exact> -> turn-by-turn (with the map) to the nearest
//                                                    match, or to the place on the map (shown)
//   DIRECTIONS_STOP                                  -> stops navigation
//   DIRECTIONS_VIEW: <map|minimal|zoomin|zoomout>    -> map / one-line view / zoom
//   PLACE: <place> | <kind|brand|exact>              -> where the nearest match is, with the user
//   OPEN: <captions|ai|search|calc|notes|remind|saved|nav> -> shows that tab
//   LANGUAGE: <hud|hearing> | <ja|en|pt>             -> HUD language / language the mic listens for
//   CALC: <formula>                                  -> exact result, added to the answer
//   CONVERT: <value> | <from> | <to>                 -> units / live currency, added to the answer
//
// Public API:
//   ClaudeOnPC(settings:charts:actions:)
//   isConfigured: Bool                       // enabled + URL + token filled in
//   ask(_ question:) async throws -> String  // answer text, action lines removed
//   checkConnection() async -> String?       // nil = OK, else the error
//   enum ClaudeBridgeError

import Foundation

enum ClaudeBridgeError: LocalizedError {
    case notConfigured
    case badURL
    case server(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Claude PC link not set up"
        case .badURL: return "PC address is not a valid URL"
        case .server(let message): return message
        case .http(let code): return "PC bridge error (HTTP \(code))"
        }
    }
}

@MainActor
final class ClaudeOnPC {

    // MARK: - Dependencies

    private let settings: HudSettings
    private let charts: ChartService
    private let actions: AiActions

    /// What the HUD shows right now (Nav map place), added to each question's context.
    var situation: (() -> String?)?

    /// First question after launch starts a fresh Claude conversation.
    private var needsNewSession = true

    init(
        settings: HudSettings,
        charts: ChartService,
        actions: AiActions
    ) {
        self.settings = settings
        self.charts = charts
        self.actions = actions
    }

    var isConfigured: Bool {
        settings.useClaudeOnPC && !trimmed(settings.pcBridgeUrl).isEmpty && !trimmed(settings.pcBridgeToken).isEmpty
    }

    // MARK: - Asking

    func ask(_ question: String) async throws -> String {
        guard isConfigured else { throw ClaudeBridgeError.notConfigured }
        let prompt = "\(AiContext.line(language: settings.language, situation: situation?()))\n\(question)"
        let body: [String: Any] = [
            "prompt": prompt,
            "system": HudConstants.claudeInstructions,
            "newSession": needsNewSession,
        ]
        let reply = try await send(path: "/ask", body: body, timeout: HudConstants.claudeBridgeTimeoutSeconds)
        needsNewSession = false
        guard let answer = reply["answer"] as? String else { throw ClaudeBridgeError.server("Empty answer") }
        return await runActions(in: answer)
    }

    /// Calls /health. nil when the PC answers with the right token.
    func checkConnection() async -> String? {
        do {
            _ = try await send(path: "/health", body: nil, timeout: HudConstants.searchTimeoutSeconds)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Action lines

    /// Carries out IMAGE/STOCK/CHART/SAVE/LISTEN/DIRECTIONS/CALC/CONVERT lines and returns the text without them.
    private func runActions(in answer: String) async -> String {
        var kept: [String] = []
        for line in answer.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if let formula = value(trimmedLine, "CALC:") {
                kept.append(actions.calculate(formula))
            } else if let spec = value(trimmedLine, "CONVERT:") {
                let parts = spec.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 3, let amount = Double(parts[0].replacingOccurrences(of: ",", with: "")) {
                    kept.append(await actions.convert(amount, parts[1], parts[2]))
                }
            } else if trimmedLine.uppercased() == "LISTEN_STOP" {
                _ = actions.stopListening()
            } else if let view = value(trimmedLine, "DIRECTIONS_VIEW:") {
                _ = actions.directionsView(view.lowercased())
            } else if let spec = value(trimmedLine, "PLACE:") {
                let parts = spec.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                _ = await actions.showPlace(parts[0], Self.match(parts, at: 1))
            } else if let tab = value(trimmedLine, "OPEN:") {
                _ = actions.openTab(tab.lowercased())
            } else if let spec = value(trimmedLine, "LANGUAGE:") {
                let parts = spec.lowercased().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { _ = actions.setLanguage(parts[0], parts[1]) }
            } else if trimmedLine.uppercased() == "DIRECTIONS_STOP" {
                _ = actions.stopDirections()
            } else if let spec = value(trimmedLine, "DIRECTIONS:") {
                let parts = spec.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let mode = parts.count > 1 ? DirectionsMode(rawValue: parts[1].lowercased()) ?? .walking : .walking
                if parts[0].lowercased() == "shown" {
                    _ = await actions.goToShownPlace(mode)
                } else {
                    _ = await actions.startDirections(parts[0], Self.match(parts, at: 2), mode)
                }
            } else if let title = value(trimmedLine, "LISTEN:") {
                // "LISTEN: Meeting | ja | 17:08 | 17:09" — language, start, stop (all optional).
                let parts = title.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let language = parts.count > 1 && HudLanguage(rawValue: parts[1].lowercased()) != nil ? parts[1].lowercased() : nil
                let times = ListeningScheduler.times(
                    start: parts.count > 2 ? parts[2] : "", stop: parts.count > 3 ? parts[3] : "", minutes: 0
                )
                _ = actions.startListening(parts[0], language, times.start, times.stop)
            } else if let terms = value(trimmedLine, "IMAGE:") {
                actions.showPicture(terms, kept.last ?? terms)
            } else if let spec = value(trimmedLine, "STOCK:") {
                runStock(spec)
            } else if let spec = value(trimmedLine, "CHART:") {
                runChart(spec)
            } else if let title = value(trimmedLine, "SAVE:") {
                _ = actions.saveChat(title)
            } else {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "kind" / "brand" / "exact" at parts[index]; kind when missing.
    private static func match(_ parts: [String], at index: Int) -> PlaceMatch {
        parts.count > index ? PlaceMatch(rawValue: parts[index].lowercased()) ?? .kind : .kind
    }

    private func value(_ line: String, _ marker: String) -> String? {
        guard line.uppercased().hasPrefix(marker) else { return nil }
        let rest = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// "Toyota | year"
    private func runStock(_ spec: String) {
        let parts = spec.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let range = parts.count > 1 ? StockRange(rawValue: parts[1]) ?? .month : .month
        Task {
            if let chart = try? await charts.stockChart(name: parts[0], range: range) { actions.showChart(chart) }
        }
    }

    /// "Japan population | million | 2000=126.9; 2010=128.1; 2020=126.1"
    private func runChart(_ spec: String) {
        let parts = spec.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return }
        let points = parts[2].components(separatedBy: ";").compactMap { pair -> ChartPoint? in
            let sides = pair.components(separatedBy: "=")
            guard sides.count == 2,
                  let number = Double(sides[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
            else { return nil }
            return ChartPoint(label: String(sides[0].trimmingCharacters(in: .whitespaces).prefix(8)), value: number)
        }
        if let chart = try? charts.chart(title: parts[0], unit: parts[1], points: points) { actions.showChart(chart) }
    }

    // MARK: - HTTP

    private func send(path: String, body: [String: Any]?, timeout: Double) async throws -> [String: Any] {
        let base = trimmed(settings.pcBridgeUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path), url.scheme != nil else { throw ClaudeBridgeError.badURL }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(trimmed(settings.pcBridgeToken))", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let message = json["error"] as? String { throw ClaudeBridgeError.server(message) }
        guard status == 200 else { throw ClaudeBridgeError.http(status) }
        return json
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

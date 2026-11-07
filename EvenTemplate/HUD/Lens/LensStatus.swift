// LensStatus.swift
//
// Builds the status bar shown in the bottom-right corner of every screen:
//   "23:44 ● G82% P64%"
// time · listening dot (blinks while the mic is listening) · glasses battery
// (G, when connected) · phone battery (P). Ticks every statusTickSeconds and
// hands the text to LensController, which only redraws when it changed (and
// LensPusher then only re-sends the status element).
//
// Public API:
//   LensStatus(session:isListening:onText:)
//   start() / stop()

import Foundation
import UIKit

@MainActor
final class LensStatus {

    private let session: BluetoothSession
    private let isListening: () -> Bool
    private let onText: (String) -> Void
    private var ticker: Task<Void, Never>?
    private var blinkOn = false

    init(session: BluetoothSession, isListening: @escaping () -> Bool, onText: @escaping (String) -> Void) {
        self.session = session
        self.isListening = isListening
        self.onText = onText
    }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(HudConstants.statusTickSeconds * 1_000_000_000))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        blinkOn.toggle()
        onText(text())
    }

    private func text() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var parts = [formatter.string(from: Date())]
        if isListening() { parts.append(blinkOn ? "●" : "○") }
        if let glasses = session.glasses.battery?.level { parts.append("G\(glasses)%") }
        let phone = UIDevice.current.batteryLevel
        if phone >= 0 { parts.append("P\(Int((phone * 100).rounded()))%") }
        return parts.joined(separator: " ")
    }
}

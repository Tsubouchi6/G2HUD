// LensPusher.swift
//
// The only place that sends HUD text to the glasses. Rate-limits pushes to
// `HudConstants.lensPushIntervalMs` and skips text that didn't change, so
// fast-changing content (live captions) can't flood Bluetooth.
//
// Public API:
//   LensPusher(session:)
//   show(_ text: String)    // throttled; the newest text always wins
//   clear()                 // blank the lens immediately

import Foundation

@MainActor
final class LensPusher {

    // MARK: - State

    private let session: BluetoothSession
    private var pendingText: String?
    private var lastSentText = ""
    private var lastSendDate = Date.distantPast
    private var sendTask: Task<Void, Never>?

    init(session: BluetoothSession) {
        self.session = session
    }

    // MARK: - API

    func show(_ text: String) {
        pendingText = text
        guard sendTask == nil else { return }  // a send is already scheduled; it will pick this up

        let elapsedMs = Date().timeIntervalSince(lastSendDate) * 1000
        let waitMs = max(0, Double(HudConstants.lensPushIntervalMs) - elapsedMs)
        sendTask = Task { [weak self] in
            if waitMs > 0 { try? await Task.sleep(nanoseconds: UInt64(waitMs * 1_000_000)) }
            guard let self, !Task.isCancelled else { return }
            self.sendTask = nil
            self.sendPending()
        }
    }

    func clear() {
        sendTask?.cancel()
        sendTask = nil
        pendingText = nil
        lastSentText = ""
        let sdk = session.sdk
        Task { try? await sdk.clearDisplay() }
    }

    // MARK: - Sending

    private func sendPending() {
        guard let text = pendingText else { return }
        pendingText = nil
        guard text != lastSentText else { return }
        lastSentText = text
        lastSendDate = Date()
        let sdk = session.sdk
        Task { try? await sdk.displayText(text) }
    }
}

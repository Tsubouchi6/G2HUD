// LensPusher.swift
//
// The only place that sends HUD text to the glasses. Rate-limits pushes to
// `HudConstants.lensPushIntervalMs` and skips text that didn't change, so
// fast-changing content (live captions) can't flood Bluetooth.
//
// Public API:
//   LensPusher(session:)
//   show(_ text: String)                    // throttled; the newest text always wins
//   showImage(tiles:caption:)               // picture tiles + caption under them
//   clear()                                 // blank the lens immediately

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

    /// Replaces the lens with a picture (already cut into tiles) and a caption.
    /// Any pending text is dropped; the next `show` after `clear` redraws text.
    func showImage(tiles: [LensImageTile], caption: String) {
        clear()
        let sdk = session.sdk
        let captionEvent = Self.layoutEvent([
            "layoutType": "positioned_text",
            "text": caption,
            "x": 0, "y": HudConstants.imageCaptionY,
            "width": HudConstants.lensWidthPx, "height": HudConstants.imageCaptionHeight,
        ])
        let tileEvents = tiles.map { tile in
            Self.layoutEvent([
                "layoutType": "bitmap_view",
                "data": tile.png.base64EncodedString(),
                "x": tile.x, "y": tile.y, "width": tile.width, "height": tile.height,
            ])
        }
        Task {
            try? await sdk.displayEvent(captionEvent)
            // The glasses queue image sends one at a time (template reconcile loop).
            for event in tileEvents { try? await sdk.displayEvent(event) }
        }
    }

    /// A main-view display event in the template's layout format.
    private static func layoutEvent(_ layout: [String: Any]) -> DisplayEventRequest {
        DisplayEventRequest(values: ["view": "main", "layout": layout])
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

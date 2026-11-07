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
//   showScene(text:picture:spot:)           // text block + picture placed by LensPictureSpot (one scene)
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

    /// Last chat scene sent (the G2 code diffs elements by id, so unchanged
    /// parts, especially the slow picture, aren't re-sent). nil = text mode.
    private var lastScene: (text: String, picture: Data, spot: LensPictureSpot)?

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

    /// Text and a picture placed by `spot`, as one scene frame (template
    /// DeviceManager "scene" event: elements with per-id change marks;
    /// G2.applySceneFrame skips "unchanged" ones, so the slow picture is only
    /// re-sent when it changes). Used by the AI chat and the nav mini-map.
    func showScene(text: String, picture: Data, spot: LensPictureSpot) {
        sendTask?.cancel()
        sendTask = nil
        pendingText = nil
        if let last = lastScene, last.text == text, last.picture == picture, last.spot == spot { return }

        // Coming from text mode or another layout: paint everything fresh.
        let replay = lastScene == nil || lastScene?.spot != spot
        let textChange = replay ? "created" : (lastScene?.text == text ? "unchanged" : "updated")
        let pictureChange = replay ? "created" : (lastScene?.picture == picture ? "unchanged" : "updated")
        lastScene = (text, picture, spot)
        let textBox = spot.textBox, pictureBox = spot.pictureBox
        lastSentText = ""  // the next plain-text push must be sent again

        let scene: [String: Any] = [
            "appId": "g2hud",
            "replay": replay,
            "removed": [String](),
            "elements": [
                [
                    "id": "scene-text", "type": "text", "text": text, "change": textChange,
                    "box": ["x": textBox.x, "y": textBox.y, "w": textBox.width, "h": textBox.height],
                ],
                [
                    "id": "scene-picture", "type": "image", "data": picture.base64EncodedString(), "change": pictureChange,
                    "box": ["x": pictureBox.x, "y": pictureBox.y, "w": pictureBox.width, "h": pictureBox.height],
                ],
            ],
        ]
        let sdk = session.sdk
        Task { try? await sdk.displayEvent(DisplayEventRequest(values: ["view": "main", "scene": scene])) }
    }

    /// A main-view display event in the template's layout format.
    private static func layoutEvent(_ layout: [String: Any]) -> DisplayEventRequest {
        DisplayEventRequest(values: ["view": "main", "layout": layout])
    }

    func clear() {
        lastScene = nil
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
        // Leaving a chat scene: a "clear_view" layout makes the template drop the
        // stored scene and blank its elements (plain displayText bypasses that,
        // and the old scene would come back after the head-up dashboard).
        let leavingScene = lastScene != nil
        lastScene = nil
        Task {
            if leavingScene { try? await sdk.displayEvent(Self.layoutEvent(["layoutType": "clear_view"])) }
            try? await sdk.displayText(text)
        }
    }
}

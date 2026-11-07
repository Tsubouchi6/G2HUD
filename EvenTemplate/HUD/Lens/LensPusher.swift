// LensPusher.swift
//
// The only place that sends HUD content to the glasses. Every screen is one
// scene frame (template DeviceManager "scene" event) with up to four
// elements: the tab's text, an optional picture (chat picture / nav map),
// the tab bar in the bottom-left corner, and the status bar in the bottom-right. Each element carries a
// change mark, so the G2 code only re-sends what changed (G2.applySceneFrame
// skips "unchanged"; the slow picture isn't re-sent when only the time ticks).
// Pushes are rate-limited to `HudConstants.lensPushIntervalMs`; the newest wins.
//
// Public API:
//   LensPusher(session:)
//   show(LensFrame)                          // throttled; the newest frame always wins
//   showImage(tiles:caption:)               // full-lens picture tiles + caption (legacy layout)
//   clear()                                 // blank the lens immediately
//   struct LensFrame { text, textBox, picture, pictureBox, tabBar, status }

import Foundation

/// One screen: the tab's text in `textBox`, an optional picture, the tab bar and the status bar.
struct LensFrame: Equatable {
    var text: String
    var textBox: LensPictureSpot.Box
    var picture: Data?
    var pictureBox: LensPictureSpot.Box?
    var tabBar: String
    var status: String
}

@MainActor
final class LensPusher {

    // MARK: - State

    private let session: BluetoothSession
    private var pendingFrame: LensFrame?
    /// Last frame sent; nil after a clear or a full-lens picture (next frame paints fresh).
    private var lastFrame: LensFrame?
    private var lastSendDate = Date.distantPast
    private var sendTask: Task<Void, Never>?

    init(session: BluetoothSession) {
        self.session = session
    }

    // MARK: - API

    func show(_ frame: LensFrame) {
        pendingFrame = frame
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
        lastFrame = nil
        sendTask?.cancel()
        sendTask = nil
        pendingFrame = nil
        let sdk = session.sdk
        Task { try? await sdk.clearDisplay() }
    }

    // MARK: - Sending

    private func sendPending() {
        guard let frame = pendingFrame else { return }
        pendingFrame = nil
        guard frame != lastFrame else { return }
        let previous = lastFrame
        lastFrame = frame
        lastSendDate = Date()

        // Coming from nothing (start, clear, full-lens picture) or a different
        // layout: paint everything fresh; otherwise mark only what changed.
        let replay = previous == nil || previous?.textBox != frame.textBox || previous?.pictureBox != frame.pictureBox
        func change(_ same: Bool) -> String { replay ? "created" : (same ? "unchanged" : "updated") }

        var elements: [[String: Any]] = [
            Self.element(id: "content", type: "text", box: frame.textBox,
                         change: change(previous?.text == frame.text), payload: ["text": frame.text]),
            Self.element(id: "tabbar", type: "text", box: Self.tabBarBox,
                         change: change(previous?.tabBar == frame.tabBar), payload: ["text": frame.tabBar]),
            Self.element(id: "status", type: "text", box: Self.statusBox,
                         change: change(previous?.status == frame.status), payload: ["text": frame.status]),
        ]
        var removed: [String] = []
        if let picture = frame.picture, let box = frame.pictureBox {
            elements.append(Self.element(id: "picture", type: "image", box: box,
                                         change: change(previous?.picture == picture),
                                         payload: ["data": picture.base64EncodedString()]))
        } else if previous?.picture != nil {
            removed.append("picture")
        }

        let scene: [String: Any] = ["appId": "g2hud", "replay": replay, "removed": removed, "elements": elements]
        let sdk = session.sdk
        Task { try? await sdk.displayEvent(DisplayEventRequest(values: ["view": "main", "scene": scene])) }
    }

    private static let tabBarBox = LensPictureSpot.Box(
        x: 0, y: HudConstants.statusBarY,
        width: HudConstants.tabBarWidthPx, height: HudConstants.statusBarHeightPx
    )

    private static let statusBox = LensPictureSpot.Box(
        x: HudConstants.statusBarX, y: HudConstants.statusBarY,
        width: HudConstants.statusBarWidthPx, height: HudConstants.statusBarHeightPx
    )

    private static func element(id: String, type: String, box: LensPictureSpot.Box, change: String,
                                payload: [String: Any]) -> [String: Any] {
        var element: [String: Any] = [
            "id": id, "type": type, "change": change,
            "box": ["x": box.x, "y": box.y, "w": box.width, "h": box.height],
        ]
        element.merge(payload) { _, new in new }
        return element
    }
}

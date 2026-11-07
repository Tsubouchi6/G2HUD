// LensTab.swift
//
// What every full-screen lens tab provides. A tab only describes its content;
// LensController decides what part of it is visible and sends it to the glasses.
//
// Public API:
//   struct LensPage { lines, anchor, picture, pictureSpot }
//   enum LensPictureSpot: bottom (chat) / left (navigation mini-map) — boxes in lens px
//   protocol LensTab
//     id, title, voiceNames
//     page() -> LensPage
//     onChange: (() -> Void)?     // tab calls this when its content changes

import Foundation

struct LensPage {
    /// Logical lines (LensController wraps long ones).
    var lines: [String]
    var anchor: LensAnchor
    /// A picture (PNG, chatPictureWidthPx x chatPictureHeightPx) shown under the
    /// newest lines while the page is scrolled to its newest end. Chats use it
    /// so a chart or photo sits in the conversation like a message.
    var picture: Data? = nil
    var pictureSpot: LensPictureSpot = .bottom
}

/// Where a page's picture goes and where its text goes around it.
enum LensPictureSpot {
    /// Chat: text on top, a 400x100 picture under the newest lines.
    case bottom
    /// Navigation: a 200x200 mini-map on the left, text in a column on the right.
    case left

    struct Box {
        let x: Int, y: Int, width: Int, height: Int
    }

    var pictureBox: Box {
        switch self {
        case .bottom:
            return Box(x: 0, y: HudConstants.chatPictureY,
                       width: HudConstants.chatPictureWidthPx, height: HudConstants.chatPictureHeightPx)
        case .left:
            return Box(x: 0, y: HudConstants.navMiniMapY,
                       width: HudConstants.navMiniMapSizePx, height: HudConstants.navMiniMapSizePx)
        }
    }

    var textBox: Box {
        switch self {
        case .bottom:
            return Box(x: 0, y: 0, width: HudConstants.lensWidthPx, height: HudConstants.chatPictureY)
        case .left:
            return Box(x: HudConstants.navTextX, y: 0,
                       width: HudConstants.lensWidthPx - HudConstants.navTextX, height: HudConstants.lensHeightPx)
        }
    }

    /// Text lines that fit, and text units per line.
    var textLines: Int {
        self == .bottom ? HudConstants.chatLinesAbovePicture : HudConstants.lensLinesPerScreen
    }
    var lineUnits: Int {
        self == .bottom ? HudConstants.lensLineUnits : HudConstants.navTextLineUnits
    }
}

@MainActor
protocol LensTab: AnyObject {
    /// Stable id, e.g. "captions".
    var id: String { get }
    /// Short name shown when switching to the tab, e.g. "字幕".
    var title: String { get }
    /// Spoken names that open this tab ("字幕", "captions", ...), lowercased.
    var voiceNames: [String] { get }
    /// Current content.
    func page() -> LensPage
    /// Set by LensController; the tab calls it after its content changes.
    var onChange: (() -> Void)? { get set }
}

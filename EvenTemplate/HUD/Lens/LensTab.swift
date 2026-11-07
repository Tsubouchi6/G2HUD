// LensTab.swift
//
// What every full-screen lens tab provides. A tab only describes its content;
// LensController decides what part of it is visible and sends it to the glasses.
//
// Public API:
//   struct LensPage { lines, anchor, picture, pictureSpot, header }
//   enum LensPictureSpot: bottom (chat) / top (navigation map) / corner (nav arrow) — boxes in lens px
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
    /// Title shown in the tab bar (bottom-left) instead of the tab's name, e.g. the
    /// search query or the open Saved item, so it doesn't take a text line.
    var header: String? = nil
}

/// Where a page's picture goes and where its text goes around it.
enum LensPictureSpot {
    /// Chat: text on top, a 400x100 picture under the newest lines.
    case bottom
    /// Navigation: the biggest picture (400x200) at the top, one text line under it.
    case top
    /// Minimal navigation: a small turn arrow top-left, two text lines beside it.
    case corner

    struct Box: Equatable {
        let x: Int, y: Int, width: Int, height: Int
    }

    var pictureBox: Box {
        switch self {
        case .bottom:
            return Box(x: 0, y: HudConstants.chatPictureY,
                       width: HudConstants.chatPictureWidthPx, height: HudConstants.chatPictureHeightPx)
        case .top:
            return Box(x: HudConstants.navMapX, y: 0,
                       width: HudConstants.navMapWidthPx, height: HudConstants.navMapHeightPx)
        case .corner:
            return Box(x: 0, y: 0, width: HudConstants.navArrowSizePx, height: HudConstants.navArrowSizePx)
        }
    }

    var textBox: Box {
        switch self {
        case .bottom:
            return Box(x: 0, y: 0, width: HudConstants.lensWidthPx, height: HudConstants.chatPictureY)
        case .top:
            return Box(x: 0, y: HudConstants.navTextY,
                       width: HudConstants.lensWidthPx, height: HudConstants.lensContentHeightPx - HudConstants.navTextY)
        case .corner:
            let x = HudConstants.navArrowSizePx + 8
            return Box(x: x, y: 0, width: HudConstants.lensWidthPx - x, height: HudConstants.navArrowSizePx)
        }
    }

    /// Text lines that fit, and text units per line.
    var textLines: Int {
        switch self {
        case .bottom: return HudConstants.chatLinesAbovePicture
        case .top: return HudConstants.navTextLines
        case .corner: return 2
        }
    }
    var lineUnits: Int {
        let width = textBox.width
        return HudConstants.lensLineUnits * width / HudConstants.lensWidthPx
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

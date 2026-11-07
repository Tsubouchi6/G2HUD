// LensTextLayout.swift
//
// Estimates how text wraps on the lens so tabs can scroll by whole lines.
// The firmware wraps text itself and exposes no font metrics, so widths are
// approximated: ASCII = 1 unit, everything else (kana, kanji) = 2 units.
//
// Public API:
//   LensTextLayout.wrap(_ text: String) -> [String]
//   LensTextLayout.truncate(_ text: String, units: Int) -> String
//   LensTextLayout.window(_ lines: [String], anchor:, scroll:, height:) -> LensWindow

import Foundation

/// Which end of a page stays pinned when it's longer than the screen.
enum LensAnchor {
    case top     // lists: first item first
    case bottom  // chat/captions: newest at the bottom
}

struct LensWindow {
    let lines: [String]
    /// Largest useful scroll offset for this page.
    let maxScroll: Int
}

enum LensTextLayout {

    // MARK: - Width

    static func units(of character: Character) -> Int {
        character.isASCII ? 1 : 2
    }

    static func units(of text: String) -> Int {
        text.reduce(0) { $0 + units(of: $1) }
    }

    // MARK: - Wrapping

    /// Splits on newlines, then wraps each line at `HudConstants.lensLineUnits`.
    static func wrap(_ text: String) -> [String] {
        let limit = HudConstants.lensLineUnits
        var result: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            var current = ""
            var currentUnits = 0
            for character in rawLine {
                let width = units(of: character)
                if currentUnits + width > limit {
                    result.append(current)
                    current = ""
                    currentUnits = 0
                }
                current.append(character)
                currentUnits += width
            }
            result.append(current)
        }
        return result
    }

    /// Cuts `text` to at most `units` wide, adding "…" when cut.
    static func truncate(_ text: String, units limit: Int) -> String {
        guard units(of: text) > limit else { return text }
        var result = ""
        var used = 0
        for character in text {
            let width = units(of: character)
            if used + width > limit - 1 { break }
            result.append(character)
            used += width
        }
        return result + "…"
    }

    // MARK: - Scrolling

    /// Picks the visible slice of already-wrapped lines.
    /// `scroll` counts lines away from the anchored end (0 = anchored end).
    static func window(_ lines: [String], anchor: LensAnchor, scroll: Int, height: Int) -> LensWindow {
        guard lines.count > height, height > 0 else {
            return LensWindow(lines: lines, maxScroll: 0)
        }
        let maxScroll = lines.count - height
        let offset = min(max(scroll, 0), maxScroll)
        let start = anchor == .top ? offset : maxScroll - offset
        return LensWindow(lines: Array(lines[start ..< start + height]), maxScroll: maxScroll)
    }
}

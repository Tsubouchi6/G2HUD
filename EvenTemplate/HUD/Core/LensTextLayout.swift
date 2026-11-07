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
    /// Latin text breaks at the last space so words stay whole; text without
    /// spaces (Japanese) breaks between any two characters, as it should.
    static func wrap(_ text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            result.append(contentsOf: wrapLine(rawLine))
        }
        return result
    }

    private static func wrapLine(_ line: String) -> [String] {
        let limit = HudConstants.lensLineUnits
        var result: [String] = []
        var current = ""
        for character in line {
            if units(of: current) + units(of: character) > limit {
                if character == " " {
                    // The break falls on a space: drop it.
                    result.append(current)
                    current = ""
                    continue
                }
                if let lastSpace = current.lastIndex(of: " "), lastSpace != current.startIndex {
                    // Move the unfinished word to the next line.
                    result.append(String(current[..<lastSpace]))
                    current = String(current[current.index(after: lastSpace)...])
                } else {
                    // One word longer than a line, or no spaces (Japanese): hard break.
                    result.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        result.append(current)
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

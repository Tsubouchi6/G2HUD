// LensTab.swift
//
// What every full-screen lens tab provides. A tab only describes its content;
// LensController decides what part of it is visible and sends it to the glasses.
//
// Public API:
//   struct LensPage { lines, anchor }
//   protocol LensTab
//     id, title, voiceNames
//     page() -> LensPage
//     onChange: (() -> Void)?     // tab calls this when its content changes

import Foundation

struct LensPage {
    /// Logical lines (LensController wraps long ones).
    var lines: [String]
    var anchor: LensAnchor
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

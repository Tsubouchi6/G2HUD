// LensController.swift
//
// Owns the full-screen lens tabs: which one is active, its scroll position,
// short banners (tab name, notices), and turning a tab's page into the exact
// text sent to the glasses. Also publishes that text so the phone can show a
// live preview of the lens.
//
// Public API:
//   LensController(pusher:)
//   @Published activeIndex: Int, previewText: String, isActive: Bool
//   tabs: [LensTab]
//   setTabs(_:)
//   activate() / deactivate()
//   next() / previous() / select(id:) -> Bool / tab(named:) -> LensTab?
//   scroll(linesUp:) / scroll(linesDown:)
//   showBanner(_ text: String, seconds: Double)
//   render()

import Foundation

@MainActor
final class LensController: ObservableObject {

    // MARK: - Published state

    @Published private(set) var activeIndex = 0
    @Published private(set) var previewText = ""
    @Published private(set) var isActive = false

    private(set) var tabs: [LensTab] = []

    // MARK: - Private state

    private let pusher: LensPusher
    /// Lines away from the page's anchored end, per tab id.
    private var scrollOffsets: [String: Int] = [:]
    private var banner: String?
    private var bannerTask: Task<Void, Never>?

    init(pusher: LensPusher) {
        self.pusher = pusher
    }

    // MARK: - Setup

    func setTabs(_ newTabs: [LensTab]) {
        tabs = newTabs
        for tab in tabs {
            let id = tab.id
            tab.onChange = { [weak self] in self?.tabDidChange(id) }
        }
        activeIndex = 0
        render()
    }

    func activate() {
        isActive = true
        render()
    }

    func deactivate() {
        isActive = false
        bannerTask?.cancel()
        banner = nil
        pusher.clear()
    }

    // MARK: - Navigation

    var activeTab: LensTab? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
    }

    func next() { move(by: 1) }
    func previous() { move(by: -1) }

    /// Jumps to a tab by id. Returns false if there is no such tab.
    @discardableResult
    func select(id: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        switchTo(index)
        return true
    }

    /// Finds a tab by one of its spoken names (exact match, lowercased).
    func tab(named spoken: String) -> LensTab? {
        let key = spoken.lowercased()
        return tabs.first { $0.voiceNames.contains(key) }
    }

    func scroll(linesUp count: Int) { scrollActive(by: count, towardsOlder: true) }
    func scroll(linesDown count: Int) { scrollActive(by: count, towardsOlder: false) }

    // MARK: - Banner

    /// Shows `text` as the top line for `seconds`, then removes it.
    func showBanner(_ text: String, seconds: Double = HudConstants.lensBannerSeconds) {
        banner = text
        render()
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.banner = nil
            self.render()
        }
    }

    // MARK: - Rendering

    /// Rebuilds the lens text from the active tab and pushes it.
    func render() {
        guard let tab = activeTab else { return }
        let page = tab.page()
        let wrapped = page.lines.flatMap(LensTextLayout.wrap)
        let height = HudConstants.lensLinesPerScreen - (banner == nil ? 0 : 1)

        let offset = scrollOffsets[tab.id] ?? 0
        let window = LensTextLayout.window(wrapped, anchor: page.anchor, scroll: offset, height: height)
        if offset > window.maxScroll { scrollOffsets[tab.id] = window.maxScroll }

        var lines = window.lines
        if let banner { lines.insert(banner, at: 0) }
        let text = lines.joined(separator: "\n")

        previewText = text
        if isActive { pusher.show(text) }
    }

    // MARK: - Private

    private func tabDidChange(_ id: String) {
        guard activeTab?.id == id else { return }
        // New content on an anchored page snaps back to the newest/first lines.
        scrollOffsets[id] = 0
        render()
    }

    private func move(by delta: Int) {
        guard !tabs.isEmpty else { return }
        switchTo(((activeIndex + delta) % tabs.count + tabs.count) % tabs.count)
    }

    private func switchTo(_ index: Int) {
        activeIndex = index
        showBanner("◀ \(tabs[index].title) ▶")
    }

    private func scrollActive(by count: Int, towardsOlder: Bool) {
        guard let tab = activeTab else { return }
        let page = tab.page()
        // "Up" means towards the top of the page for both anchors.
        let delta = page.anchor == .bottom ? (towardsOlder ? count : -count) : (towardsOlder ? -count : count)
        scrollOffsets[tab.id] = max(0, (scrollOffsets[tab.id] ?? 0) + delta)
        render()
    }
}

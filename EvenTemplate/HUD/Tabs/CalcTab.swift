// CalcTab.swift
//
// Lens tab: calculator. Shows "expression = result" history, newest at the bottom.
//
// Public API: CalcTab()  — LensTab with id "calc"; calculate(_ expression:)

import Foundation

@MainActor
final class CalcTab: LensTab {

    let id = "calc"
    let title = "計算"
    let voiceNames = ["計算", "けいさん", "電卓", "でんたく", "calc", "calculator"]
    var onChange: (() -> Void)?

    private var history: [String] = []
    private static let maxHistory = 50

    func page() -> LensPage {
        LensPage(lines: history.isEmpty ? ["(say: メガネ 計算 12かける35)"] : history, anchor: .bottom)
    }

    func calculate(_ expression: String) {
        let line: String
        do {
            let value = try Calculator.evaluate(expression)
            line = "\(expression) = \(Calculator.format(value))"
        } catch {
            line = "\(expression): \(error.localizedDescription)"
        }
        history.append(line)
        if history.count > Self.maxHistory { history.removeFirst() }
        onChange?()
    }
}

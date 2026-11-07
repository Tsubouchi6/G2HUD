// CalcTab.swift
//
// Lens tab: calculator. Shows "expression = result" history, newest at the bottom.
// Follow-ups ("plus 5", "×2", "答え÷3") continue from the last answer.
// The AI's calculate/convert results are listed here too.
//
// Public API: CalcTab()  — LensTab with id "calc"
//   calculate(_ expression:) -> String          // the history line ("12*3 = 36" or the error)
//   convert(_ value:, from:, to:) async -> String // "5 km = 3.106856 mi" (units, or currency at live rates)

import Foundation

@MainActor
final class CalcTab: LensTab {

    let id = "calc"
    var title: String { HudText.t(.tabCalc) }
    let voiceNames = ["計算", "けいさん", "電卓", "でんたく", "calc", "calculator", "calculadora"]
    var onChange: (() -> Void)?

    private var history: [String] = []
    private var lastResult: Double?
    private static let maxHistory = 50

    func page() -> LensPage {
        LensPage(lines: history.isEmpty ? [HudText.t(.calcHint)] : history, anchor: .bottom)
    }

    @discardableResult
    func calculate(_ expression: String) -> String {
        let line: String
        do {
            let value = try Calculator.evaluate(expression, previous: lastResult)
            lastResult = value
            line = "\(expression) = \(Calculator.format(value))"
        } catch {
            line = "\(expression): \(error.localizedDescription)"
        }
        record(line)
        return line
    }

    func convert(_ value: Double, from: String, to: String) async -> String {
        let line: String
        do {
            let result = try await UnitConversion.convert(value, from: from, to: to)
            lastResult = result
            line = "\(Calculator.format(value)) \(from) = \(Calculator.format(result)) \(to)"
        } catch {
            line = "\(Calculator.format(value)) \(from) → \(to): \(error.localizedDescription)"
        }
        record(line)
        return line
    }

    private func record(_ line: String) {
        history.append(line)
        if history.count > Self.maxHistory { history.removeFirst() }
        onChange?()
    }
}

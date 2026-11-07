// ChartRenderer.swift
//
// Draws a line or bar chart (Swift Charts) into a PNG sized for a picture
// inside the AI chat (chatPictureWidthPx x chatPictureHeightPx). White on black: the glasses show it as bright green, and
// black is see-through. Labels are kept few and large, since the lens is
// only ~23 pixels per degree.
//
// Public API:
//   ChartRenderer.png(points:kind:) -> Data?
//   struct ChartPoint { label, value }
//   enum ChartKind: line / bar

import Charts
import SwiftUI

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

enum ChartKind {
    case line
    case bar
}

@MainActor
enum ChartRenderer {

    static func png(points: [ChartPoint], kind: ChartKind) -> Data? {
        guard !points.isEmpty else { return nil }
        // Sized for a picture inside the AI chat (not the full lens).
        let width = CGFloat(HudConstants.chatPictureWidthPx)
        let height = CGFloat(HudConstants.chatPictureHeightPx)

        let chart: AnyView = kind == .line
            ? AnyView(LineChartView(points: points))
            : AnyView(BarChartView(points: points))
        let view = chart
            .padding(6)
            .frame(width: width, height: height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}

// MARK: - Chart views

/// Line chart on an index x axis (evenly spaced); only the first and last
/// labels are shown so they stay readable.
private struct LineChartView: View {
    let points: [ChartPoint]

    var body: some View {
        Chart(Array(points.enumerated()), id: \.element.id) { index, point in
            LineMark(x: .value("i", index), y: .value("v", point.value))
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(.white)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: [0, points.count - 1]) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), points.indices.contains(index) {
                        Text(points[index].label)
                            .font(.system(size: HudConstants.chartLabelFontPt))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .chartYAxis { valueAxis }
    }
}

/// Bar chart, one labelled bar per point.
private struct BarChartView: View {
    let points: [ChartPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("label", point.label), y: .value("v", point.value))
                .foregroundStyle(.white)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: HudConstants.chartLabelFontPt))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .chartYAxis { valueAxis }
    }
}

/// Shared y axis: three values on the right with faint grid lines.
private var valueAxis: some AxisContent {
    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
        AxisGridLine().foregroundStyle(.white.opacity(0.35))
        AxisValueLabel()
            .font(.system(size: HudConstants.chartLabelFontPt))
            .foregroundStyle(.white)
    }
}

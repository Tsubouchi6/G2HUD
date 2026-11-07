// ArrowRenderer.swift
//
// Draws the minimal-navigation turn arrow: a white arrow on black (black is
// see-through on the lens), rotated to any angle, so it can point exactly at
// the next turn instead of the 8 text arrows.
//
// Public API: ArrowRenderer.png(degrees:) -> Data?   // 0 = straight ahead, clockwise

import UIKit

enum ArrowRenderer {

    static func png(degrees: Double) -> Data? {
        let side = CGFloat(HudConstants.navArrowSizePx)
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.translateBy(x: side / 2, y: side / 2)
            cg.rotate(by: degrees * .pi / 180)
            // Arrow pointing up: head plus a shaft.
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: 0, y: -side * 0.44))
            arrow.addLine(to: CGPoint(x: side * 0.3, y: -side * 0.08))
            arrow.addLine(to: CGPoint(x: side * 0.1, y: -side * 0.08))
            arrow.addLine(to: CGPoint(x: side * 0.1, y: side * 0.42))
            arrow.addLine(to: CGPoint(x: -side * 0.1, y: side * 0.42))
            arrow.addLine(to: CGPoint(x: -side * 0.1, y: -side * 0.08))
            arrow.addLine(to: CGPoint(x: -side * 0.3, y: -side * 0.08))
            arrow.closeSubpath()
            cg.addPath(arrow)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillPath()
        }.pngData()
    }
}

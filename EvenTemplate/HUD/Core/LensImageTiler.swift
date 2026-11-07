// LensImageTiler.swift
//
// Prepares a picture for the lens. The G2 firmware only accepts image
// containers up to 200x100 px (hardware-verified in the template's G2.swift,
// maxImageTileW/H), so a picture is fitted into a 2x2 grid of tiles and each
// tile is sent as its own PNG. The glasses turn them into 16-level green.
//
// Public API:
//   LensImageTiler.tiles(from imageData: Data) -> [LensImageTile]
//   struct LensImageTile { png, x, y, width, height }   // lens pixel coordinates

import UIKit

struct LensImageTile {
    let png: Data
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

enum LensImageTiler {

    /// Scales the image to fit the tile grid (keeping its shape, centered on
    /// black, which is see-through on the lens) and cuts it into tiles.
    static func tiles(from imageData: Data) -> [LensImageTile] {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else { return [] }

        let tileW = HudConstants.imageTileWidthPx
        let tileH = HudConstants.imageTileHeightPx
        let gridW = tileW * HudConstants.imageTilesAcross
        let gridH = tileH * HudConstants.imageTilesDown

        // 1. Fit the whole picture into the grid area.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let fitted = UIGraphicsImageRenderer(size: CGSize(width: gridW, height: gridH), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: gridW, height: gridH))
            let scale = min(CGFloat(gridW) / image.size.width, CGFloat(gridH) / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (CGFloat(gridW) - size.width) / 2, y: (CGFloat(gridH) - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
        guard let cgImage = fitted.cgImage else { return [] }

        // 2. Cut it into tiles, row by row.
        var result: [LensImageTile] = []
        for row in 0 ..< HudConstants.imageTilesDown {
            for column in 0 ..< HudConstants.imageTilesAcross {
                let rect = CGRect(x: column * tileW, y: row * tileH, width: tileW, height: tileH)
                guard let piece = cgImage.cropping(to: rect),
                      let png = UIImage(cgImage: piece).pngData()
                else { continue }
                result.append(LensImageTile(
                    png: png,
                    x: HudConstants.imageOriginX + column * tileW,
                    y: HudConstants.imageOriginY + row * tileH,
                    width: tileW,
                    height: tileH
                ))
            }
        }
        return result
    }
}

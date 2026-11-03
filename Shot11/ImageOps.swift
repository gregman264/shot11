import UIKit
import CoreGraphics

enum ImageOps {
    /// Recadre au carré (centre) et redimensionne à `out` pixels de côté.
    static func squareCenter(_ img: UIImage, out: Int) -> UIImage {
        let w = img.size.width
        let h = img.size.height
        let s = min(w, h)
        let k = CGFloat(out) / s
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt)
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            img.draw(in: CGRect(x: -(w - s) / 2 * k, y: -(h - s) / 2 * k, width: w * k, height: h * k))
        }
    }

    /// Extrait un carré (en pixels de `img`) et le redimensionne à `out`.
    static func crop(_ img: UIImage, rect: CGRect, out: Int) -> UIImage {
        let k = CGFloat(out) / rect.width
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt)
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            img.draw(in: CGRect(x: -rect.minX * k, y: -rect.minY * k,
                                width: img.size.width * k, height: img.size.height * k))
        }
    }

    /// Pixels RGBA d'une version réduite (carrée) de l'image.
    static func rgba(_ img: UIImage, side: Int) -> [UInt8]? {
        guard let cg = img.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? data : nil
    }
}

import UIKit
import CoreImage
import Vision

/// Réglages du fond uniforme (enregistrés dans les réglages de l'appli).
struct BgSettings {
    var uniformity: Double
    var fixed: Bool
    var r: Double
    var g: Double
    var b: Double

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: "bgEnabled")
    }

    static func load() -> BgSettings {
        let d = UserDefaults.standard
        let u = (d.object(forKey: "bgUniformity") as? Double) ?? 0.6
        let r = (d.object(forKey: "bgR") as? Double) ?? 0.20
        let g = (d.object(forKey: "bgG") as? Double) ?? 0.21
        let b = (d.object(forKey: "bgB") as? Double) ?? 0.23
        return BgSettings(uniformity: u, fixed: d.bool(forKey: "bgFixed"), r: r, g: g, b: b)
    }
}

/// Remplace le fond par la même couleur en plus uniforme, en gardant un peu de texture.
/// Le sujet est détecté par Vision (iOS 17 minimum) ; sur iOS 16 l'image reste inchangée.
enum Background {
    private static let ctx = CIContext()

    static func apply(_ img: UIImage, _ s: BgSettings) -> UIImage {
        if #available(iOS 17.0, *) {
            return applyModern(img, s) ?? img
        }
        return img
    }

    @available(iOS 17.0, *)
    private static func applyModern(_ img: UIImage, _ s: BgSettings) -> UIImage? {
        guard let cg = img.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let obs = request.results?.first else { return nil }
        guard let buf = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler) else { return nil }

        // Couleur du fond : médiane des pixels situés hors du sujet.
        guard let med = backgroundMedian(img, buf) else { return nil }

        let input = CIImage(cgImage: cg)
        let extent = input.extent

        var base = input
        var flatR = med.0
        var flatG = med.1
        var flatB = med.2
        if s.fixed {
            let kr = min(max(s.r / max(med.0, 0.02), 0.5), 2.0)
            let kg = min(max(s.g / max(med.1, 0.02), 0.5), 2.0)
            let kb = min(max(s.b / max(med.2, 0.02), 0.5), 2.0)
            if let m = CIFilter(name: "CIColorMatrix") {
                m.setValue(base, forKey: kCIInputImageKey)
                m.setValue(CIVector(x: CGFloat(kr), y: 0, z: 0, w: 0), forKey: "inputRVector")
                m.setValue(CIVector(x: 0, y: CGFloat(kg), z: 0, w: 0), forKey: "inputGVector")
                m.setValue(CIVector(x: 0, y: 0, z: CGFloat(kb), w: 0), forKey: "inputBVector")
                m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                if let o = m.outputImage { base = o }
            }
            flatR = s.r
            flatG = s.g
            flatB = s.b
        }

        let flat = CIImage(color: CIColor(red: CGFloat(flatR), green: CGFloat(flatG), blue: CGFloat(flatB))).cropped(to: extent)
        guard let dissolve = CIFilter(name: "CIDissolveTransition") else { return nil }
        dissolve.setValue(base, forKey: kCIInputImageKey)
        dissolve.setValue(flat, forKey: kCIInputTargetImageKey)
        dissolve.setValue(NSNumber(value: s.uniformity), forKey: kCIInputTimeKey)
        guard let bgImage = dissolve.outputImage else { return nil }

        var mask = CIImage(cvPixelBuffer: buf)
        let maskExtent = mask.extent
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(mask.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(NSNumber(value: 1.2), forKey: kCIInputRadiusKey)
            if let o = blur.outputImage { mask = o.cropped(to: maskExtent) }
        }

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(input, forKey: kCIInputImageKey)
        blend.setValue(bgImage, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let out = blend.outputImage,
              let result = ctx.createCGImage(out, from: extent) else { return nil }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }

    /// Médiane RVB (0...1) des pixels hors sujet ; nil si le fond est quasi invisible.
    private static func backgroundMedian(_ img: UIImage, _ buf: CVPixelBuffer) -> (Double, Double, Double)? {
        let n = 96
        guard let px = ImageOps.rgba(img, side: n) else { return nil }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let mw = CVPixelBufferGetWidth(buf)
        let mh = CVPixelBufferGetHeight(buf)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        let fmt = CVPixelBufferGetPixelFormatType(buf)
        if fmt != kCVPixelFormatType_OneComponent32Float && fmt != kCVPixelFormatType_OneComponent8 { return nil }

        var rs: [UInt8] = []
        var gs: [UInt8] = []
        var bs: [UInt8] = []
        for y in 0..<n {
            let my = min(mh - 1, y * mh / n)
            let row = base.advanced(by: my * bpr)
            for x in 0..<n {
                let mx = min(mw - 1, x * mw / n)
                var v: Float = 1
                if fmt == kCVPixelFormatType_OneComponent32Float {
                    v = row.assumingMemoryBound(to: Float.self)[mx]
                } else {
                    v = Float(row.assumingMemoryBound(to: UInt8.self)[mx]) / 255
                }
                if v < 0.4 {
                    let i = (y * n + x) * 4
                    rs.append(px[i])
                    gs.append(px[i + 1])
                    bs.append(px[i + 2])
                }
            }
        }
        if rs.count < n * n / 50 { return nil }
        rs.sort()
        gs.sort()
        bs.sort()
        let k = rs.count / 2
        return (Double(rs[k]) / 255, Double(gs[k]) / 255, Double(bs[k]) / 255)
    }
}

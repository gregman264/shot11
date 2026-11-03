import UIKit

/// Détection du vêtement : le fond = le pourtour de l'image, le vêtement = le centre.
/// Chaque pixel est classé selon la couleur dont il se rapproche le plus.
enum Detector {
    static let margin: CGFloat = 0.04

    static func autoBox(for img: UIImage) -> CropBox {
        let s = img.size.width
        let n = 192
        var bb: (x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat)? = nil
        if let px = ImageOps.rgba(img, side: n) {
            bb = detect(px, w: n, h: n)
        }
        return boxFrom(bb, s)
    }

    static func boxFrom(_ bb: (x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat)?, _ s: CGFloat) -> CropBox {
        guard let b = bb else { return CropBox(x: s * 0.05, y: s * 0.05, side: s * 0.9) }
        let w = (b.x1 - b.x0) * s
        let h = (b.y1 - b.y0) * s
        let cx = (b.x0 + b.x1) / 2 * s
        let cy = (b.y0 + b.y1) / 2 * s
        var side = max(w, h) * (1 + 2 * margin)
        side = min(max(side, s * 0.25), s)
        let x = min(max(cx - side / 2, 0), s - side)
        let y = min(max(cy - side / 2, 0), s - side)
        return CropBox(x: x, y: y, side: side)
    }

    static func boxBlur(_ f: [Float], _ w: Int, _ h: Int) -> [Float] {
        var t = [Float](repeating: 0, count: f.count)
        var o = [Float](repeating: 0, count: f.count)
        for y in 0..<h {
            let r = y * w
            for x in 0..<w {
                let a = x > 0 ? x - 1 : 0
                let b = x < w - 1 ? x + 1 : w - 1
                t[r + x] = (f[r + a] + f[r + x] + f[r + b]) / 3
            }
        }
        for y in 0..<h {
            let a = (y > 0 ? y - 1 : 0) * w
            let b = (y < h - 1 ? y + 1 : h - 1) * w
            let r = y * w
            for x in 0..<w {
                o[r + x] = (t[a + x] + t[r + x] + t[b + x]) / 3
            }
        }
        return o
    }

    static func morph(_ m: [UInt8], _ w: Int, _ h: Int, erode: Bool) -> [UInt8] {
        var o = [UInt8](repeating: 0, count: m.count)
        for y in 0..<h {
            for x in 0..<w {
                var v: UInt8 = erode ? 1 : 0
                outer: for dy in -1...1 {
                    for dx in -1...1 {
                        let yy = y + dy
                        let xx = x + dx
                        var s: UInt8 = erode ? 1 : 0
                        if yy >= 0 && yy < h && xx >= 0 && xx < w {
                            s = m[yy * w + xx]
                        }
                        if erode {
                            if s == 0 { v = 0; break outer }
                        } else {
                            if s == 1 { v = 1; break outer }
                        }
                    }
                }
                o[y * w + x] = v
            }
        }
        return o
    }

    struct Comp {
        var area: Int
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
    }

    static func detect(_ d: [UInt8], w: Int, h: Int) -> (x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat)? {
        let n = w * h
        let band = max(2, Int((Double(min(w, h)) * 0.05).rounded()))

        var chans: [[Float]] = []
        for c in 0..<3 {
            var a = [Float](repeating: 0, count: n)
            for p in 0..<n { a[p] = Float(d[p * 4 + c]) }
            chans.append(boxBlur(a, w, h))
        }
        var key = [Int](repeating: 0, count: n)
        for p in 0..<n {
            let r = Int(chans[0][p])
            let g = Int(chans[1][p])
            let b = Int(chans[2][p])
            let q = min(15, max(0, (b - r + 64) >> 3))
            key[p] = ((r >> 4) << 12) | ((g >> 4) << 8) | ((b >> 4) << 4) | q
        }

        var hb = [Float](repeating: 0, count: 65536)
        var hf = [Float](repeating: 0, count: 65536)
        var nb: Float = 0
        var nf: Float = 0
        let c0 = Int((Double(w) * 0.3).rounded())
        let c1 = Int((Double(w) * 0.7).rounded())
        let d0 = Int((Double(h) * 0.3).rounded())
        let d1 = Int((Double(h) * 0.7).rounded())
        for y in 0..<h {
            let ey = y < band || y >= h - band
            for x in 0..<w {
                let p = y * w + x
                if ey || x < band || x >= w - band {
                    hb[key[p]] += 1
                    nb += 1
                } else if x >= c0 && x < c1 && y >= d0 && y < d1 {
                    hf[key[p]] += 1
                    nf += 1
                }
            }
        }
        if nb == 0 || nf == 0 { return nil }

        var f = [Float](repeating: 0, count: n)
        for p in 0..<n {
            let k = key[p]
            let pf = (hf[k] + 0.5) / nf
            let pb = (hb[k] + 0.5) / nb
            f[p] = Float(log(Double(pf / pb)))
        }
        f = boxBlur(boxBlur(f, w, h), w, h)

        var m = [UInt8](repeating: 0, count: n)
        for p in 0..<n { m[p] = f[p] > 0 ? 1 : 0 }
        m = morph(morph(m, w, h, erode: true), w, h, erode: false)

        var lab = [Int32](repeating: 0, count: n)
        var stack = [Int](repeating: 0, count: n)
        var comps: [Comp] = []
        for s in 0..<n {
            if m[s] == 0 || lab[s] != 0 { continue }
            let id = Int32(comps.count + 1)
            var sp = 0
            var area = 0
            var x0 = w
            var y0 = h
            var x1 = -1
            var y1 = -1
            stack[sp] = s
            sp += 1
            lab[s] = id
            while sp > 0 {
                sp -= 1
                let p = stack[sp]
                let x = p % w
                let y = p / w
                area += 1
                if x < x0 { x0 = x }
                if x > x1 { x1 = x }
                if y < y0 { y0 = y }
                if y > y1 { y1 = y }
                if x > 0 && m[p - 1] == 1 && lab[p - 1] == 0 { lab[p - 1] = id; stack[sp] = p - 1; sp += 1 }
                if x < w - 1 && m[p + 1] == 1 && lab[p + 1] == 0 { lab[p + 1] = id; stack[sp] = p + 1; sp += 1 }
                if y > 0 && m[p - w] == 1 && lab[p - w] == 0 { lab[p - w] = id; stack[sp] = p - w; sp += 1 }
                if y < h - 1 && m[p + w] == 1 && lab[p + w] == 0 { lab[p + w] = id; stack[sp] = p + w; sp += 1 }
            }
            comps.append(Comp(area: area, x0: x0, y0: y0, x1: x1, y1: y1))
        }
        guard let maxA = comps.map({ $0.area }).max() else { return nil }
        if Double(maxA) < Double(n) * 0.02 { return nil }

        var X0 = w
        var Y0 = h
        var X1 = -1
        var Y1 = -1
        var tot = 0
        for c in comps {
            if Double(c.area) < Double(maxA) * 0.2 { continue }
            tot += c.area
            X0 = min(X0, c.x0)
            Y0 = min(Y0, c.y0)
            X1 = max(X1, c.x1)
            Y1 = max(Y1, c.y1)
        }
        if Double(tot) > Double(n) * 0.93 { return nil }
        let fw = CGFloat(w)
        let fh = CGFloat(h)
        return (CGFloat(X0) / fw, CGFloat(Y0) / fh, CGFloat(X1 + 1) / fw, CGFloat(Y1 + 1) / fh)
    }
}

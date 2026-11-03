import SwiftUI
import UIKit

final class Store: ObservableObject {
    @Published var screen: Screen = .home
    @Published var articles: [Article] = []
    @Published var covers: [String: UIImage] = [:]
    @Published var counts: [String: Int] = [:]
    @Published var current: Article? = nil
    @Published var defs: [StepDef] = Steps.defs(.top)
    @Published var step: Int = 0
    @Published var thumbs: [UIImage?] = Array(repeating: nil, count: 11)
    @Published var busy = false
    @Published var adjustBox = CropBox(x: 0, y: 0, side: 1)
    @Published var regenZooms = true
    @Published var zipURL: URL? = nil
    @Published var allZipURL: URL? = nil
    @Published var allZipBuilding = false
    @Published var toast: String? = nil
    @Published var exportMode: ExportMode = .folderPerRef

    var sources: [Int: UIImage] = [:]
    var returnToDetail = false
    weak var camera: CameraService?

    private let ioQueue = DispatchQueue(label: "shot11.io", qos: .utility)
    private var toastWork: DispatchWorkItem?

    init() {
        if let raw = UserDefaults.standard.string(forKey: "exportMode"), let m = ExportMode(rawValue: raw) {
            exportMode = m
        }
        loadLibrary()
    }

    var ref: String { current?.ref ?? "" }

    var suggestedRef: String {
        nextRef(UserDefaults.standard.string(forKey: "lastRef") ?? "")
    }

    var doneCount: Int {
        thumbs.compactMap { $0 }.count
    }

    /// Les 4 zooms sont tirés de l'image d'origine de la face (étape 0).
    func srcIndex(_ i: Int) -> Int {
        defs[i].auto ? 0 : i
    }

    // MARK: Disque

    private var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("Shot11", isDirectory: true)
            .appendingPathComponent("articles", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func dir(_ id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func photoURL(_ id: String, _ i: Int) -> URL {
        dir(id).appendingPathComponent(String(format: "%02d.jpg", i))
    }

    private func thumbURL(_ id: String, _ i: Int) -> URL {
        dir(id).appendingPathComponent(String(format: "%02d.t.jpg", i))
    }

    private func srcURL(_ id: String, _ i: Int) -> URL {
        dir(id).appendingPathComponent(String(format: "%02d.src.jpg", i))
    }

    private func writeMeta(_ a: Article) {
        let d = dir(a.id)
        ioQueue.async {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(a) {
                try? data.write(to: d.appendingPathComponent("meta.json"))
            }
        }
    }

    private func mutateCurrent(_ f: (inout Article) -> Void) {
        guard var a = current else { return }
        f(&a)
        current = a
        if let k = articles.firstIndex(where: { $0.id == a.id }) { articles[k] = a }
        writeMeta(a)
    }

    func loadLibrary() {
        ioQueue.async {
            let fm = FileManager.default
            var list: [Article] = []
            var cnt: [String: Int] = [:]
            var cov: [String: UIImage] = [:]
            let dirs = (try? fm.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil)) ?? []
            for d in dirs {
                let metaURL = d.appendingPathComponent("meta.json")
                guard let data = try? Data(contentsOf: metaURL),
                      let a = try? JSONDecoder().decode(Article.self, from: data) else { continue }
                list.append(a)
                var n = 0
                for i in 0..<11 where fm.fileExists(atPath: self.photoURL(a.id, i).path) { n += 1 }
                cnt[a.id] = n
                for i in 0..<11 {
                    if let img = UIImage(contentsOfFile: self.thumbURL(a.id, i).path) {
                        cov[a.id] = img
                        break
                    }
                }
            }
            list.sort { $0.created > $1.created }
            DispatchQueue.main.async {
                self.articles = list
                self.counts = cnt
                self.covers = cov
            }
        }
    }

    // MARK: Articles

    private func setCurrent(_ a: Article) {
        current = a
        defs = Steps.defs(a.kind)
        thumbs = Array(repeating: nil, count: 11)
        sources = [:]
        zipURL = nil
    }

    func createArticle(ref raw: String, kind: Garment) {
        var r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            r = "article_" + f.string(from: Date())
        }
        let a = Article(id: UUID().uuidString, ref: r, kind: kind, created: Date(), wb: nil, boxes: nil)
        UserDefaults.standard.set(r, forKey: "lastRef")
        articles.insert(a, at: 0)
        counts[a.id] = 0
        allZipURL = nil
        setCurrent(a)
        writeMeta(a)
        returnToDetail = false
        enter(0)
    }

    func open(_ a: Article) {
        setCurrent(a)
        ioQueue.async {
            var arr: [UIImage?] = Array(repeating: nil, count: 11)
            for i in 0..<11 {
                arr[i] = UIImage(contentsOfFile: self.thumbURL(a.id, i).path)
            }
            DispatchQueue.main.async {
                if self.current?.id == a.id { self.thumbs = arr }
                self.goRecap()
            }
        }
    }

    func goHome() {
        current = nil
        screen = .home
    }

    func deleteCurrent() {
        guard let a = current else { return }
        let d = dir(a.id)
        articles.removeAll { $0.id == a.id }
        counts[a.id] = nil
        covers[a.id] = nil
        allZipURL = nil
        ioQueue.async { try? FileManager.default.removeItem(at: d) }
        goHome()
    }

    private func savePhoto(_ i: Int, jpeg: Data, thumb: UIImage, box: CropBox, S: CGFloat) {
        guard let a = current else { return }
        thumbs[i] = thumb
        counts[a.id] = thumbs.compactMap { $0 }.count
        if i == 0 || covers[a.id] == nil { covers[a.id] = thumb }
        let pu = photoURL(a.id, i)
        let tu = thumbURL(a.id, i)
        let tj = thumb.jpegData(compressionQuality: 0.7)
        ioQueue.async {
            try? jpeg.write(to: pu)
            if let t = tj { try? t.write(to: tu) }
        }
        let nb = NBox(x: Double(box.x / S), y: Double(box.y / S), side: Double(box.side / S))
        mutateCurrent { art in
            var b = art.boxes ?? [:]
            b[String(i)] = nb
            art.boxes = b
        }
        zipURL = nil
        allZipURL = nil
    }

    /// Mémorise avec l'article les gains de blanc utilisés pour la dernière photo.
    private func rememberWhiteBalance() {
        guard let a = current, let g = camera?.currentGains() else { return }
        if a.wb == g { return }
        mutateCurrent { $0.wb = g }
    }

    private func storedBox(_ i: Int, S: CGFloat) -> CropBox? {
        guard let n = current?.boxes?[String(i)] else { return nil }
        return CropBox(x: CGFloat(n.x) * S, y: CGFloat(n.y) * S, side: CGFloat(n.side) * S)
    }

    static func zoomBox(_ d: StepDef, face b: CropBox) -> CropBox {
        let cs = b.side * 0.6
        return CropBox(x: b.x + d.fx * (b.side - cs), y: b.y + d.fy * (b.side - cs), side: cs)
    }

    // MARK: Navigation

    func enter(_ i: Int) {
        step = i
        screen = .camera
    }

    func nextTodo(from: Int) -> Int? {
        for k in 1...11 {
            let i = (from + k + 11) % 11
            if !defs[i].auto && thumbs[i] == nil { return i }
        }
        return nil
    }

    func advance() {
        if returnToDetail {
            returnToDetail = false
            goRecap()
            return
        }
        if let n = nextTodo(from: step) { enter(n) } else { goRecap() }
    }

    func goRecap() {
        returnToDetail = false
        screen = .recap
        prepareZip()
    }

    func continueArticle() {
        returnToDetail = false
        enter(nextTodo(from: -1) ?? 0)
    }

    /// Touche sur une vignette.
    /// Depuis le détail de l'article : recadrage (ou prise si la photo n'existe pas encore).
    /// Depuis la caméra : refaire la photo, ou recadrer pour les zooms automatiques.
    func tapStep(_ i: Int) {
        let fromDetail = (screen == .recap)
        returnToDetail = fromDetail
        if !defs[i].auto && thumbs[i] == nil {
            enter(i)
        } else if fromDetail || defs[i].auto {
            openAdjust(i, box: nil)
        } else {
            enter(i)
        }
    }

    func previousPhoto() {
        var i = step - 1
        while i >= 0 {
            if !defs[i].auto { returnToDetail = false; enter(i); return }
            i -= 1
        }
        showToast("C’est la première photo")
    }

    func retake(_ i: Int) {
        sources[i] = nil
        enter(i)
    }

    func cancelAdjust() {
        if returnToDetail { goRecap() } else { screen = .camera }
    }

    // MARK: Capture

    func handleCapture(_ data: Data) {
        let idx = step
        let def = defs[idx]
        guard let a = current else { busy = false; return }
        let srcFile = srcURL(a.id, idx)
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = UIImage(data: data) else {
                DispatchQueue.main.async { self.busy = false }
                return
            }
            let s = Int(min(img.size.width, img.size.height))
            let src = ImageOps.squareCenter(img, out: min(s, 2400))
            let srcJPEG = src.jpegData(compressionQuality: 0.88)
            let S = src.size.width
            if def.crop {
                let box = Detector.autoBox(for: src)
                DispatchQueue.main.async {
                    self.rememberWhiteBalance()
                    if let sj = srcJPEG { self.ioQueue.async { try? sj.write(to: srcFile) } }
                    self.sources[idx] = src
                    self.finishOpenAdjust(idx, src: src, box: box, fresh: true)
                    self.busy = false
                }
            } else {
                let full = CropBox(x: 0, y: 0, side: S)
                let sq = ImageOps.squareCenter(src, out: 1600)
                let jpg = sq.jpegData(compressionQuality: 0.93)
                let th = ImageOps.squareCenter(sq, out: 120)
                DispatchQueue.main.async {
                    self.rememberWhiteBalance()
                    if let sj = srcJPEG { self.ioQueue.async { try? sj.write(to: srcFile) } }
                    if let j = jpg { self.savePhoto(idx, jpeg: j, thumb: th, box: full, S: S) }
                    self.busy = false
                    self.advance()
                }
            }
        }
    }

    // MARK: Ajustement / recadrage

    /// Ouvre l'écran de recadrage d'une photo existante (ou d'une prise fraîche si `box` est fourni).
    func openAdjust(_ i: Int, box: CropBox?) {
        guard let a = current else { return }
        let si = srcIndex(i)
        if let s = sources[si] {
            finishOpenAdjust(i, src: s, box: box, fresh: false)
            return
        }
        let url = srcURL(a.id, si)
        ioQueue.async {
            let img = UIImage(contentsOfFile: url.path)
            DispatchQueue.main.async {
                if let img = img {
                    self.sources[si] = img
                    self.finishOpenAdjust(i, src: img, box: box, fresh: false)
                } else if self.defs[i].auto {
                    self.showToast("Reprends d’abord la photo Face")
                    self.enter(0)
                } else {
                    self.showToast("Photo d’origine introuvable : refais-la")
                    self.enter(i)
                }
            }
        }
    }

    private func finishOpenAdjust(_ i: Int, src: UIImage, box: CropBox?, fresh: Bool) {
        let S = src.size.width
        if let b = box {
            adjustBox = b
        } else if let stored = storedBox(i, S: S) {
            adjustBox = stored
        } else {
            adjustBox = defaultBox(i, src: src)
        }
        regenZooms = (i == 0) && (fresh || thumbs[1] == nil)
        step = i
        screen = .adjust(i)
    }

    private func defaultBox(_ i: Int, src: UIImage) -> CropBox {
        let S = src.size.width
        if defs[i].auto {
            let face = storedBox(0, S: S) ?? CropBox(x: 0, y: 0, side: S)
            return Store.zoomBox(defs[i], face: face)
        }
        if defs[i].crop { return Detector.autoBox(for: src) }
        return CropBox(x: 0, y: 0, side: S)
    }

    func resetBox(_ i: Int) {
        guard let src = sources[srcIndex(i)] else { return }
        adjustBox = defaultBox(i, src: src)
    }

    func setSide(_ side: CGFloat, S: CGFloat) {
        let b = adjustBox
        let sd = min(max(side, S * 0.2), S)
        let cx = b.x + b.side / 2
        let cy = b.y + b.side / 2
        adjustBox = CropBox(x: min(max(cx - sd / 2, 0), S - sd),
                            y: min(max(cy - sd / 2, 0), S - sd),
                            side: sd)
    }

    func validateAdjust(_ i: Int) {
        guard let src = sources[srcIndex(i)] else { return }
        let S = src.size.width
        let box = adjustBox
        let regen = (i == 0) && regenZooms
        let list = defs
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [(Int, Data, UIImage, CropBox)] = []
            func add(_ k: Int, _ b: CropBox) {
                let img = ImageOps.crop(src, rect: CGRect(x: b.x, y: b.y, width: b.side, height: b.side), out: 1600)
                if let d = img.jpegData(compressionQuality: 0.93) {
                    results.append((k, d, ImageOps.squareCenter(img, out: 120), b))
                }
            }
            add(i, box)
            if regen {
                for (k, d) in list.enumerated() where d.auto {
                    add(k, Store.zoomBox(d, face: box))
                }
            }
            DispatchQueue.main.async {
                for r in results { self.savePhoto(r.0, jpeg: r.1, thumb: r.2, box: r.3, S: S) }
                self.busy = false
                self.step = i
                self.advance()
            }
        }
    }

    // MARK: Export

    func setExportMode(_ m: ExportMode) {
        exportMode = m
        UserDefaults.standard.set(m.rawValue, forKey: "exportMode")
        allZipURL = nil
        if screen == .recap { prepareZip() } else { zipURL = nil }
    }

    /// Noms de fichiers : REF_01.jpg ... REF_11.jpg, avec ou sans dossier par référence.
    private func exportEntries(_ list: [Article], mode: ExportMode) -> [(name: String, url: URL)] {
        var out: [(name: String, url: URL)] = []
        var used: [String: Int] = [:]
        for a in list {
            var r = safeRef(a.ref)
            if let n = used[r] {
                used[r] = n + 1
                r += "_" + String(n + 1)
            } else {
                used[r] = 1
            }
            for i in 0..<11 {
                let u = photoURL(a.id, i)
                if FileManager.default.fileExists(atPath: u.path) {
                    let file = r + "_" + Steps.number(i) + ".jpg"
                    let name = (mode == .folderPerRef) ? (r + "/" + file) : file
                    out.append((name: name, url: u))
                }
            }
        }
        return out
    }

    func prepareZip() {
        guard let a = current else { return }
        zipURL = nil
        let mode = exportMode
        let name = safeRef(a.ref)
        ioQueue.async {
            let entries = self.exportEntries([a], mode: mode)
            if entries.isEmpty { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".zip")
            do {
                try ZipWriter.write(entries: entries, to: url)
                DispatchQueue.main.async {
                    if self.current?.id == a.id && self.exportMode == mode { self.zipURL = url }
                }
            } catch {}
        }
    }

    func prepareAllZip() {
        if allZipBuilding { return }
        allZipBuilding = true
        allZipURL = nil
        let list = Array(articles.reversed())
        let mode = exportMode
        ioQueue.async {
            let entries = self.exportEntries(list, mode: mode)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Shot11_tous_les_articles_" + f.string(from: Date()) + ".zip")
            var ok = false
            if !entries.isEmpty {
                do {
                    try ZipWriter.write(entries: entries, to: url)
                    ok = true
                } catch {}
            }
            DispatchQueue.main.async {
                self.allZipBuilding = false
                if ok && self.exportMode == mode { self.allZipURL = url }
                else if !ok { self.showToast("Aucune photo à exporter") }
            }
        }
    }

    // MARK: Message bref

    func showToast(_ m: String) {
        toast = m
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }
}

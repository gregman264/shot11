import SwiftUI
import UIKit

struct ExportGroup {
    var folder: String?
    var articles: [Article]
}

final class Store: ObservableObject {
    @Published var screen: Screen = .home
    @Published var articles: [Article] = []
    @Published var folders: [Folder] = []
    @Published var covers: [String: UIImage] = [:]
    @Published var counts: [String: Int] = [:]
    @Published var current: Article? = nil
    @Published var currentFolderId: String? = nil
    @Published var defs: [StepDef] = Steps.defs(.top)
    @Published var step: Int = 0
    @Published var thumbs: [UIImage?] = Array(repeating: nil, count: Steps.count)
    @Published var busy = false
    @Published var processing: String? = nil
    @Published var exporting = false
    @Published var adjustBox = CropBox(x: 0, y: 0, side: 1)
    @Published var regenZooms = true
    @Published var zipURL: URL? = nil
    @Published var toast: String? = nil
    @Published var exportMode: ExportMode = .folderPerRef
    @Published var selecting = false
    @Published var selectedArticles: Set<String> = []
    @Published var selectedFolders: Set<String> = []

    var sources: [Int: UIImage] = [:]
    var returnToDetail = false
    var backTarget: Screen = .home
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

    var requiredCount: Int {
        current?.needed ?? 13
    }

    func displayNumber(_ i: Int) -> Int {
        Steps.exportNumber(i, defect: current?.defect)
    }

    /// Les 4 zooms sont tirés de l'image d'origine de la face (étape 0).
    func srcIndex(_ i: Int) -> Int {
        Steps.isAuto(i) ? 0 : i
    }

    // MARK: Disque

    private var base: URL {
        let b = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = b.appendingPathComponent("Shot11", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private var root: URL {
        let u = base.appendingPathComponent("articles", isDirectory: true)
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

    private func writeFolders() {
        let list = folders
        let u = base.appendingPathComponent("folders.json")
        ioQueue.async {
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: u)
            }
        }
    }

    /// Modifie un article (liste, article courant et disque).
    private func update(_ id: String, _ f: (inout Article) -> Void) {
        guard let k = articles.firstIndex(where: { $0.id == id }) else { return }
        var a = articles[k]
        f(&a)
        articles[k] = a
        if current?.id == id { current = a }
        writeMeta(a)
    }

    private func mutateCurrent(_ f: (inout Article) -> Void) {
        guard let a = current else { return }
        update(a.id, f)
    }

    /// Anciens articles (11 photos) : on décale les fichiers pour faire de la place au logo et au défaut.
    private func migrate(_ a: Article) -> Article {
        if a.ver != nil { return a }
        var art = a
        let fm = FileManager.default
        let order: [(Int, Int)] = [(10, 12), (9, 10), (8, 9), (7, 8), (6, 7), (5, 6)]
        for (o, n) in order {
            let pairs: [(URL, URL)] = [
                (photoURL(a.id, o), photoURL(a.id, n)),
                (thumbURL(a.id, o), thumbURL(a.id, n)),
                (srcURL(a.id, o), srcURL(a.id, n))
            ]
            for (s, d) in pairs where fm.fileExists(atPath: s.path) {
                try? fm.removeItem(at: d)
                try? fm.moveItem(at: s, to: d)
            }
        }
        let dict: [Int: Int] = [10: 12, 9: 10, 8: 9, 7: 8, 6: 7, 5: 6]
        if let old = art.boxes {
            var nb: [String: NBox] = [:]
            for (k, v) in old {
                if let i = Int(k) {
                    nb[String(dict[i] ?? i)] = v
                }
            }
            art.boxes = nb
        }
        art.defect = false
        art.ver = 2
        if art.bg == nil { art.bg = false }
        if let data = try? JSONEncoder().encode(art) {
            try? data.write(to: dir(a.id).appendingPathComponent("meta.json"))
        }
        return art
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
                      let decoded = try? JSONDecoder().decode(Article.self, from: data) else { continue }
                let a = self.migrate(decoded)
                list.append(a)
                var n = 0
                for i in 0..<Steps.count where fm.fileExists(atPath: self.photoURL(a.id, i).path) { n += 1 }
                cnt[a.id] = n
                for i in 0..<Steps.count {
                    if let img = UIImage(contentsOfFile: self.thumbURL(a.id, i).path) {
                        cov[a.id] = img
                        break
                    }
                }
            }
            list.sort { $0.created > $1.created }
            var fl: [Folder] = []
            if let data = try? Data(contentsOf: self.base.appendingPathComponent("folders.json")),
               let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
                fl = decoded.sorted { $0.created > $1.created }
            }
            DispatchQueue.main.async {
                self.articles = list
                self.folders = fl
                self.counts = cnt
                self.covers = cov
            }
        }
    }

    // MARK: Articles

    private func setCurrent(_ a: Article) {
        current = a
        defs = Steps.defs(a.kind)
        thumbs = Array(repeating: nil, count: Steps.count)
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
        let a = Article(id: UUID().uuidString, ref: r, kind: kind, created: Date(), wb: nil, boxes: nil,
                        defect: nil, folderId: currentFolderId, bg: BgSettings.enabled, ver: 2)
        UserDefaults.standard.set(r, forKey: "lastRef")
        articles.insert(a, at: 0)
        counts[a.id] = 0
        setCurrent(a)
        writeMeta(a)
        returnToDetail = false
        enter(0)
    }

    func open(_ a: Article) {
        backTarget = (screen == .folder) ? .folder : .home
        setCurrent(a)
        ioQueue.async {
            var arr: [UIImage?] = Array(repeating: nil, count: Steps.count)
            for i in 0..<Steps.count {
                arr[i] = UIImage(contentsOfFile: self.thumbURL(a.id, i).path)
            }
            DispatchQueue.main.async {
                if self.current?.id == a.id { self.thumbs = arr }
                self.goRecap()
            }
        }
    }

    func closeArticle() {
        current = nil
        zipURL = nil
        screen = backTarget
    }

    func renameCurrent(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        mutateCurrent { $0.ref = t }
    }

    func deleteCurrent() {
        guard let a = current else { return }
        removeArticleFiles([a.id])
        closeArticle()
    }

    private func removeArticleFiles(_ ids: [String]) {
        let dirs = ids.map { dir($0) }
        articles.removeAll { ids.contains($0.id) }
        for id in ids {
            counts[id] = nil
            covers[id] = nil
        }
        ioQueue.async {
            for d in dirs { try? FileManager.default.removeItem(at: d) }
        }
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

    static func renderFinal(_ src: UIImage, _ b: CropBox, _ bg: BgSettings?) -> UIImage {
        let img = ImageOps.crop(src, rect: CGRect(x: b.x, y: b.y, width: b.side, height: b.side), out: 1600)
        if let s = bg { return Background.apply(img, s) }
        return img
    }

    // MARK: Navigation

    func enter(_ i: Int) {
        step = i
        if i == Steps.defectIndex && current?.defect == nil {
            screen = .defect
        } else {
            screen = .camera
        }
    }

    func nextTodo(from: Int) -> Int? {
        let n = Steps.count
        for k in 1...n {
            let i = (from + k + n) % n
            if Steps.isAuto(i) { continue }
            if i == Steps.defectIndex {
                if current?.defect == nil { return i }
                if current?.defect == true && thumbs[i] == nil { return i }
                continue
            }
            if thumbs[i] == nil { return i }
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

    /// Réponse à « y a-t-il un défaut ? ».
    func chooseDefect(_ yes: Bool) {
        mutateCurrent { $0.defect = yes }
        if yes {
            screen = .camera
            step = Steps.defectIndex
        } else {
            step = Steps.defectIndex
            advance()
        }
    }

    func cancelDefect() {
        goRecap()
    }

    /// Touche sur une vignette.
    /// Depuis le détail de l'article : recadrage (ou prise si la photo n'existe pas encore).
    /// Depuis la caméra : refaire la photo, ou recadrer pour les zooms automatiques.
    func tapStep(_ i: Int) {
        let fromDetail = (screen == .recap)
        returnToDetail = fromDetail
        if i == Steps.defectIndex && thumbs[i] == nil {
            step = i
            screen = .defect
        } else if !Steps.isAuto(i) && thumbs[i] == nil {
            enter(i)
        } else if fromDetail || Steps.isAuto(i) {
            openAdjust(i, box: nil)
        } else {
            enter(i)
        }
    }

    func previousPhoto() {
        var i = step - 1
        while i >= 0 {
            let skip = Steps.isAuto(i) || (i == Steps.defectIndex && current?.defect != true)
            if !skip { returnToDetail = false; enter(i); return }
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
        let useBG: BgSettings? = (a.bg == true) ? BgSettings.load() : nil
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
                var sq = ImageOps.squareCenter(src, out: 1600)
                if let bgs = useBG { sq = Background.apply(sq, bgs) }
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
                } else if Steps.isAuto(i) {
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
        if Steps.isAuto(i) {
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
        let useBG: BgSettings? = (current?.bg == true) ? BgSettings.load() : nil
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [(Int, Data, UIImage, CropBox)] = []
            func add(_ k: Int, _ b: CropBox) {
                let img = Store.renderFinal(src, b, useBG)
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

    // MARK: Fond uniforme (article existant)

    func setArticleBackground(_ on: Bool) {
        guard let a = current else { return }
        var supported = false
        if #available(iOS 17.0, *) { supported = true }
        if on && !supported {
            showToast("Le fond uniforme demande iOS 17 ou plus")
            return
        }
        update(a.id) { $0.bg = on }
        let s: BgSettings? = on ? BgSettings.load() : nil
        let boxes = a.boxes ?? [:]
        processing = "Fond : préparation…"
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [(Int, UIImage)] = []
            var cache: [Int: UIImage] = [:]
            var done = 0
            let total = boxes.count
            for i in 0..<Steps.count {
                guard FileManager.default.fileExists(atPath: self.photoURL(a.id, i).path),
                      let nb = boxes[String(i)] else { continue }
                let si = Steps.isAuto(i) ? 0 : i
                if cache[si] == nil {
                    cache[si] = UIImage(contentsOfFile: self.srcURL(a.id, si).path)
                }
                guard let src = cache[si] else { continue }
                let S = src.size.width
                let b = CropBox(x: CGFloat(nb.x) * S, y: CGFloat(nb.y) * S, side: CGFloat(nb.side) * S)
                let img = Store.renderFinal(src, b, s)
                if let d = img.jpegData(compressionQuality: 0.93) {
                    let th = ImageOps.squareCenter(img, out: 120)
                    try? d.write(to: self.photoURL(a.id, i))
                    if let tj = th.jpegData(compressionQuality: 0.7) {
                        try? tj.write(to: self.thumbURL(a.id, i))
                    }
                    results.append((i, th))
                }
                done += 1
                let msg = "Fond : " + String(done) + "/" + String(total)
                DispatchQueue.main.async { self.processing = msg }
            }
            DispatchQueue.main.async {
                if self.current?.id == a.id {
                    for r in results { self.thumbs[r.0] = r.1 }
                }
                if let first = results.first(where: { $0.0 == 0 }) { self.covers[a.id] = first.1 }
                self.zipURL = nil
                self.processing = nil
                if self.screen == .recap { self.prepareZip() }
                self.showToast(on ? "Fond uniforme appliqué" : "Fond d’origine rétabli")
            }
        }
    }

    // MARK: Sélection, dossiers, suppression

    func startSelecting() {
        selecting = true
        selectedArticles = []
        selectedFolders = []
    }

    func stopSelecting() {
        selecting = false
        selectedArticles = []
        selectedFolders = []
    }

    func toggleArticle(_ id: String) {
        if selectedArticles.contains(id) { selectedArticles.remove(id) } else { selectedArticles.insert(id) }
    }

    func toggleFolder(_ id: String) {
        if selectedFolders.contains(id) { selectedFolders.remove(id) } else { selectedFolders.insert(id) }
    }

    var selectionCount: Int { selectedArticles.count + selectedFolders.count }

    func openFolder(_ id: String) {
        stopSelecting()
        currentFolderId = id
        screen = .folder
    }

    func closeFolder() {
        stopSelecting()
        currentFolderId = nil
        screen = .home
    }

    func inFolder(_ folderId: String?) -> [Article] {
        articles.filter { $0.folderId == folderId }
    }

    func folderName(_ id: String?) -> String {
        folders.first(where: { $0.id == id })?.name ?? ""
    }

    func createFolder(name: String, withSelection: Bool) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        let f = Folder(id: UUID().uuidString, name: t, created: Date())
        folders.insert(f, at: 0)
        writeFolders()
        if withSelection {
            for id in selectedArticles { update(id) { $0.folderId = f.id } }
        }
        stopSelecting()
    }

    func moveSelected(to folderId: String?) {
        for id in selectedArticles { update(id) { $0.folderId = folderId } }
        stopSelecting()
    }

    func canRenameSelection() -> Bool {
        selectionCount == 1
    }

    func renameSelected(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if let id = selectedArticles.first, selectedArticles.count == 1, selectedFolders.isEmpty {
            update(id) { $0.ref = t }
        } else if let fid = selectedFolders.first, selectedFolders.count == 1, selectedArticles.isEmpty {
            if let k = folders.firstIndex(where: { $0.id == fid }) {
                folders[k].name = t
                writeFolders()
            }
        }
        stopSelecting()
    }

    func renameFolder(_ id: String, _ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if let k = folders.firstIndex(where: { $0.id == id }) {
            folders[k].name = t
            writeFolders()
        }
    }

    /// Supprime un dossier : ses articles sont conservés et repassent hors dossier.
    func deleteFolder(_ id: String) {
        for a in inFolder(id) { update(a.id) { $0.folderId = nil } }
        folders.removeAll { $0.id == id }
        writeFolders()
    }

    var deleteMessage: String {
        var parts: [String] = []
        let na = selectedArticles.count
        let nf = selectedFolders.count
        if na > 0 {
            let plural = (na > 1) ? "s" : ""
            parts.append("\(na) article\(plural) et leurs photos seront supprimés")
        }
        if nf > 0 {
            let plural = (nf > 1) ? "s" : ""
            parts.append("\(nf) dossier\(plural) supprimé\(plural) (les articles qu’ils contiennent sont conservés)")
        }
        return parts.joined(separator: ". ") + "."
    }

    func deleteSelected() {
        for fid in selectedFolders { deleteFolder(fid) }
        removeArticleFiles(Array(selectedArticles))
        stopSelecting()
    }

    // MARK: Export

    func setExportMode(_ m: ExportMode) {
        exportMode = m
        UserDefaults.standard.set(m.rawValue, forKey: "exportMode")
        if screen == .recap { prepareZip() } else { zipURL = nil }
    }

    /// Noms de fichiers : REF_01.jpg ... REF_13.jpg, avec ou sans dossier par référence.
    private func exportEntries(_ groups: [ExportGroup], mode: ExportMode) -> [(name: String, url: URL)] {
        var out: [(name: String, url: URL)] = []
        var usedFolders: [String: Int] = [:]
        for g in groups {
            var prefix = ""
            if let f = g.folder {
                var fn = safeRef(f)
                if let n = usedFolders[fn] {
                    usedFolders[fn] = n + 1
                    fn += "_" + String(n + 1)
                } else {
                    usedFolders[fn] = 1
                }
                prefix = fn + "/"
            }
            var used: [String: Int] = [:]
            for a in g.articles {
                var r = safeRef(a.ref)
                if let n = used[r] {
                    used[r] = n + 1
                    r += "_" + String(n + 1)
                } else {
                    used[r] = 1
                }
                for i in 0..<Steps.count {
                    let u = photoURL(a.id, i)
                    if FileManager.default.fileExists(atPath: u.path) {
                        let num = String(format: "%02d", Steps.exportNumber(i, defect: a.defect))
                        let file = r + "_" + num + ".jpg"
                        let name = prefix + ((mode == .folderPerRef) ? (r + "/" + file) : file)
                        out.append((name: name, url: u))
                    }
                }
            }
        }
        return out
    }

    /// ZIP de l'article ouvert (prêt pour le bouton de partage).
    func prepareZip() {
        guard let a = current else { return }
        zipURL = nil
        let mode = exportMode
        let name = safeRef(a.ref)
        ioQueue.async {
            let entries = self.exportEntries([ExportGroup(folder: nil, articles: [a])], mode: mode)
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

    private func zipName(_ base: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return base + "_" + f.string(from: Date()) + ".zip"
    }

    /// Construit un ZIP puis ouvre la fenêtre de partage.
    func exportZip(_ groups: [ExportGroup], name: String) {
        if exporting { return }
        exporting = true
        let mode = exportMode
        let fileName = zipName(safeRef(name))
        ioQueue.async {
            let entries = self.exportEntries(groups, mode: mode)
            var url: URL? = nil
            if !entries.isEmpty {
                let u = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try ZipWriter.write(entries: entries, to: u)
                    url = u
                } catch {}
            }
            DispatchQueue.main.async {
                self.exporting = false
                if let u = url { ShareSheet.present([u]) } else { self.showToast("Aucune photo à exporter") }
            }
        }
    }

    /// Photos seules (sans ZIP) : toutes à la suite, nommées REF_NN.jpg.
    func exportFiles(_ groups: [ExportGroup]) {
        if exporting { return }
        exporting = true
        ioQueue.async {
            let flat = [ExportGroup(folder: nil, articles: groups.flatMap { $0.articles })]
            let entries = self.exportEntries(flat, mode: .flat)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("Shot11_photos", isDirectory: true)
            try? fm.removeItem(at: tmp)
            try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            var urls: [URL] = []
            for e in entries {
                let dest = tmp.appendingPathComponent(e.name)
                do {
                    try fm.copyItem(at: e.url, to: dest)
                    urls.append(dest)
                } catch {}
            }
            DispatchQueue.main.async {
                self.exporting = false
                if urls.isEmpty { self.showToast("Aucune photo à exporter") } else { ShareSheet.present(urls) }
            }
        }
    }

    /// Groupes à exporter pour la sélection en cours.
    func selectionGroups() -> [ExportGroup] {
        var groups: [ExportGroup] = []
        for f in folders where selectedFolders.contains(f.id) {
            let list: [Article] = Array(inFolder(f.id).reversed())
            groups.append(ExportGroup(folder: f.name, articles: list))
        }
        let picked: [Article] = articles.filter { selectedArticles.contains($0.id) }
        if !picked.isEmpty {
            groups.append(ExportGroup(folder: nil, articles: Array(picked.reversed())))
        }
        return groups
    }

    /// Tout : chaque dossier devient un dossier du ZIP, les articles sans dossier sont à la racine.
    func allGroups() -> [ExportGroup] {
        var groups: [ExportGroup] = []
        for f in Array(folders.reversed()) {
            let list: [Article] = inFolder(f.id)
            if !list.isEmpty {
                groups.append(ExportGroup(folder: f.name, articles: Array(list.reversed())))
            }
        }
        let loose: [Article] = inFolder(nil)
        if !loose.isEmpty {
            groups.append(ExportGroup(folder: nil, articles: Array(loose.reversed())))
        }
        return groups
    }

    func folderGroups(_ id: String) -> [ExportGroup] {
        let list: [Article] = inFolder(id)
        return [ExportGroup(folder: nil, articles: Array(list.reversed()))]
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

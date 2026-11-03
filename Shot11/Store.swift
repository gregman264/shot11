import SwiftUI
import UIKit

final class Store: ObservableObject {
    @Published var screen: Screen = .start
    @Published var ref: String = ""
    @Published var step: Int = 0
    @Published var thumbs: [UIImage?] = Array(repeating: nil, count: 11)
    @Published var busy = false
    @Published var adjustBox = CropBox(x: 0, y: 0, side: 1)
    @Published var zipURL: URL? = nil
    @Published var toast: String? = nil
    @Published var resumeInfo: String? = nil

    var photos: [Data?] = Array(repeating: nil, count: 11)
    var sources: [Int: UIImage] = [:]
    var boxes: [Int: CropBox] = [:]
    private var toastWork: DispatchWorkItem?

    init() {
        refreshResumeInfo()
    }

    var suggestedRef: String {
        nextRef(UserDefaults.standard.string(forKey: "lastRef") ?? "")
    }

    var doneCount: Int {
        photos.filter { $0 != nil }.count
    }

    // MARK: Disque (reprise après fermeture)

    private var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("session", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func fileURL(_ i: Int) -> URL {
        dir.appendingPathComponent(String(format: "%02d.jpg", i))
    }

    private func persist(_ i: Int, _ d: Data) {
        let u = fileURL(i)
        let r = ref
        DispatchQueue.global(qos: .utility).async {
            try? d.write(to: u)
            UserDefaults.standard.set(r, forKey: "sessionRef")
        }
    }

    private func clearDisk() {
        try? FileManager.default.removeItem(at: dir)
        UserDefaults.standard.removeObject(forKey: "sessionRef")
    }

    func refreshResumeInfo() {
        var n = 0
        for i in 0..<11 where FileManager.default.fileExists(atPath: fileURL(i).path) { n += 1 }
        if n > 0, let r = UserDefaults.standard.string(forKey: "sessionRef") {
            resumeInfo = "Article \(r) en cours, \(n)/11 photos."
        } else {
            resumeInfo = nil
        }
    }

    // MARK: Session

    func startSession(ref newRef: String) {
        var r = newRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            r = "article_" + f.string(from: Date())
        }
        ref = r
        UserDefaults.standard.set(r, forKey: "lastRef")
        resetPhotos()
        clearDisk()
        enter(0)
    }

    func resume() {
        resetPhotos()
        ref = UserDefaults.standard.string(forKey: "sessionRef") ?? "article"
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var loaded: [(Int, Data, UIImage)] = []
            for i in 0..<11 {
                if let d = try? Data(contentsOf: self.fileURL(i)), let img = UIImage(data: d) {
                    loaded.append((i, d, ImageOps.squareCenter(img, out: 120)))
                }
            }
            DispatchQueue.main.async {
                for l in loaded {
                    self.photos[l.0] = l.1
                    self.thumbs[l.0] = l.2
                }
                self.busy = false
                if let n = self.nextTodo(from: -1) { self.enter(n) } else { self.goRecap() }
            }
        }
    }

    private func resetPhotos() {
        photos = Array(repeating: nil, count: 11)
        thumbs = Array(repeating: nil, count: 11)
        sources = [:]
        boxes = [:]
        zipURL = nil
    }

    func newArticle() {
        let old = ref
        clearDisk()
        resetPhotos()
        resumeInfo = nil
        UserDefaults.standard.set(old, forKey: "lastRef")
        screen = .start
    }

    // MARK: Navigation

    func enter(_ i: Int) {
        step = i
        screen = .camera
    }

    func nextTodo(from: Int) -> Int? {
        for k in 1...11 {
            let i = (from + k + 11) % 11
            if !Steps.all[i].auto && photos[i] == nil { return i }
        }
        return nil
    }

    func advance() {
        if let n = nextTodo(from: step) { enter(n) } else { goRecap() }
    }

    func goRecap() {
        screen = .recap
        prepareZip()
    }

    func tapStep(_ i: Int) {
        if Steps.all[i].auto {
            if let b = boxes[0], sources[0] != nil {
                adjustBox = b
                screen = .adjust(0)
            } else {
                showToast("Reprends la photo Face pour régénérer les zooms")
                enter(0)
            }
        } else {
            enter(i)
        }
    }

    func previousPhoto() {
        var i = step - 1
        while i >= 0 {
            if !Steps.all[i].auto { enter(i); return }
            i -= 1
        }
        showToast("C’est la première photo")
    }

    func retake(_ i: Int) {
        sources[i] = nil
        enter(i)
    }

    // MARK: Capture

    func handleCapture(_ data: Data) {
        let idx = step
        let def = Steps.all[idx]
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = UIImage(data: data) else {
                DispatchQueue.main.async { self.busy = false }
                return
            }
            if def.crop {
                let s = Int(min(img.size.width, img.size.height))
                let src = ImageOps.squareCenter(img, out: min(s, 2400))
                let box = Detector.autoBox(for: src)
                DispatchQueue.main.async {
                    self.sources[idx] = src
                    self.boxes[idx] = box
                    self.adjustBox = box
                    self.screen = .adjust(idx)
                    self.busy = false
                }
            } else {
                let sq = ImageOps.squareCenter(img, out: 1600)
                let jpg = sq.jpegData(compressionQuality: 0.93)
                let th = ImageOps.squareCenter(sq, out: 120)
                DispatchQueue.main.async {
                    if let j = jpg {
                        self.photos[idx] = j
                        self.thumbs[idx] = th
                        self.persist(idx, j)
                        self.zipURL = nil
                    }
                    self.busy = false
                    self.advance()
                }
            }
        }
    }

    // MARK: Ajustement

    func setSide(_ side: CGFloat, S: CGFloat) {
        let b = adjustBox
        let sd = min(max(side, S * 0.2), S)
        let cx = b.x + b.side / 2
        let cy = b.y + b.side / 2
        adjustBox = CropBox(x: min(max(cx - sd / 2, 0), S - sd),
                            y: min(max(cy - sd / 2, 0), S - sd),
                            side: sd)
    }

    func validateAdjust(_ idx: Int) {
        guard let src = sources[idx] else { return }
        let box = adjustBox
        boxes[idx] = box
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [(Int, Data, UIImage)] = []
            func add(_ i: Int, _ img: UIImage) {
                if let d = img.jpegData(compressionQuality: 0.93) {
                    results.append((i, d, ImageOps.squareCenter(img, out: 120)))
                }
            }
            let main = ImageOps.crop(src, rect: CGRect(x: box.x, y: box.y, width: box.side, height: box.side), out: 1600)
            add(idx, main)
            if idx == 0 {
                let cs = box.side * 0.6
                for (i, d) in Steps.all.enumerated() where d.auto {
                    let r = CGRect(x: box.x + d.fx * (box.side - cs),
                                   y: box.y + d.fy * (box.side - cs),
                                   width: cs, height: cs)
                    add(i, ImageOps.crop(src, rect: r, out: 1600))
                }
            }
            DispatchQueue.main.async {
                for r in results {
                    self.photos[r.0] = r.1
                    self.thumbs[r.0] = r.2
                    self.persist(r.0, r.1)
                }
                self.zipURL = nil
                self.busy = false
                self.step = idx
                self.advance()
            }
        }
    }

    // MARK: Export

    func prepareZip() {
        zipURL = nil
        let list = photos
        let name = safeRef(ref)
        DispatchQueue.global(qos: .userInitiated).async {
            var entries: [(String, Data)] = []
            for (i, d) in list.enumerated() {
                if let d = d { entries.append((name + "/" + Steps.all[i].file, d)) }
            }
            if entries.isEmpty { return }
            let zip = ZipWriter.make(entries)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".zip")
            try? FileManager.default.removeItem(at: url)
            do {
                try zip.write(to: url)
                DispatchQueue.main.async { self.zipURL = url }
            } catch {}
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

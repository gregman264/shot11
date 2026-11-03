import SwiftUI
import UIKit

struct CropBox {
    var x: CGFloat
    var y: CGFloat
    var side: CGFloat
}

enum Screen: Equatable {
    case home
    case start
    case camera
    case adjust(Int)
    case recap

    var usesCamera: Bool {
        switch self {
        case .camera, .adjust: return true
        default: return false
        }
    }
}

enum Garment: String, Codable, CaseIterable {
    case top
    case bottom

    var label: String { self == .top ? "Haut" : "Pantalon" }
}

/// Cadre de recadrage exprimé en fraction de l'image d'origine (indépendant de sa taille).
struct NBox: Codable {
    var x: Double
    var y: Double
    var side: Double
}

enum ExportMode: String, CaseIterable {
    case folderPerRef
    case flat

    var label: String { self == .folderPerRef ? "Un dossier par réf" : "Un seul dossier" }
}

struct Article: Codable, Identifiable {
    var id: String
    var ref: String
    var kind: Garment
    var created: Date
    var wb: [Float]? = nil
    var boxes: [String: NBox]? = nil
}

struct StepDef {
    var file: String
    var title: String
    var short: String
    var symbol: String
    var caption: String = ""
    var crop: Bool = false
    var silhouette: Int = 0          // 0 = aucune, 1 = haut, 2 = pantalon
    var auto: Bool = false
    var fx: CGFloat = 0
    var fy: CGFloat = 0
    var rotation: Double = 0
}

enum Steps {
    /// Numéro de photo sur deux chiffres : 01 ... 11
    static func number(_ i: Int) -> String {
        String(format: "%02d", i + 1)
    }

    static let files: [String] = [
        "01_face.jpg", "02_zoom_haut_gauche.jpg", "03_zoom_bas_gauche.jpg", "04_zoom_bas_droit.jpg",
        "05_zoom_haut_droit.jpg", "06_etiquette_marque.jpg", "07_etiquette_composition.jpg", "08_dos.jpg",
        "09_mesure_longueur.jpg", "10_mesure_largeur.jpg", "11_ref_stock.jpg"
    ]

    static func defs(_ g: Garment) -> [StepDef] {
        let bottom = (g == .bottom)
        let sil = bottom ? 2 : 1
        let item = bottom ? "Pantalon" : "Vêtement"
        return [
            StepDef(file: files[0], title: "Face", short: "Face", symbol: bottom ? "rectangle.portrait" : "tshirt",
                    caption: item + " entier, à plat, centré dans la silhouette.", crop: true, silhouette: sil),
            StepDef(file: files[1], title: "Zoom haut gauche", short: "Haut gauche", symbol: "tshirt", auto: true, fx: 0, fy: 0),
            StepDef(file: files[2], title: "Zoom bas gauche", short: "Bas gauche", symbol: "tshirt", auto: true, fx: 0, fy: 1),
            StepDef(file: files[3], title: "Zoom bas droit", short: "Bas droit", symbol: "tshirt", auto: true, fx: 1, fy: 1),
            StepDef(file: files[4], title: "Zoom haut droit", short: "Haut droit", symbol: "tshirt", auto: true, fx: 1, fy: 0),
            StepDef(file: files[5], title: "Étiquette marque", short: "Marque", symbol: "tag",
                    caption: bottom ? "Marque et taille bien lisibles (ceinture intérieure)." : "Col ouvert : marque et taille bien lisibles. Touche l’écran pour la netteté."),
            StepDef(file: files[6], title: "Étiquette composition", short: "Composition", symbol: "doc.text",
                    caption: "Étiquette de composition. Touche l’écran pour la netteté, ou zoome."),
            StepDef(file: files[7], title: "Dos", short: "Dos", symbol: bottom ? "rectangle.portrait" : "arrow.triangle.2.circlepath",
                    caption: item + " retourné, entier, centré dans la silhouette.", crop: true, silhouette: sil),
            StepDef(file: files[8], title: "Mesure longueur", short: "Longueur", symbol: "ruler",
                    caption: bottom ? "Mètre de la ceinture jusqu’au bas de la jambe, bien droit." : "Mètre du col jusqu’en bas, bien droit.",
                    rotation: 90),
            StepDef(file: files[9], title: "Mesure largeur", short: "Largeur", symbol: "ruler",
                    caption: bottom ? "Mètre sur la ceinture, d’un bord à l’autre, à plat." : "Mètre d’une aisselle à l’autre, à plat."),
            StepDef(file: files[10], title: "Référence stock", short: "Réf. stock", symbol: "number",
                    caption: "Étiquette de stock, bien lisible.")
        ]
    }
}

enum Theme {
    static let bg = Color(red: 0.082, green: 0.086, blue: 0.102)
    static let surface = Color(red: 0.122, green: 0.129, blue: 0.153)
    static let line = Color(red: 0.2, green: 0.212, blue: 0.247)
    static let fg = Color(red: 0.925, green: 0.918, blue: 0.894)
    static let muted = Color(red: 0.6, green: 0.612, blue: 0.651)
    static let accent = Color(red: 0.357, green: 0.486, blue: 1.0)
    static let ok = Color(red: 0.435, green: 0.827, blue: 0.604)
}

struct PrimaryButton: ButtonStyle {
    var ghost: Bool = false
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(ghost ? Theme.surface : Theme.accent)
            .foregroundColor(ghost ? Theme.fg : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

func safeRef(_ r: String) -> String {
    let folded = r.folding(options: .diacriticInsensitive, locale: nil)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    var out = ""
    for ch in folded {
        out.append(allowed.contains(ch) ? ch : "_")
    }
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "article" : trimmed
}

func nextRef(_ r: String) -> String {
    var digits = ""
    var prefix = Substring(r)
    while let last = prefix.last, last.isNumber, last.isASCII {
        digits = String(last) + digits
        prefix = prefix.dropLast()
    }
    guard !digits.isEmpty, let n = Int(digits) else { return "" }
    let next = String(n + 1)
    let padded = String(repeating: "0", count: max(0, digits.count - next.count)) + next
    return String(prefix) + padded
}

struct ExportModePicker: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let binding = Binding<ExportMode>(
            get: { store.exportMode },
            set: { store.setExportMode($0) }
        )
        return Picker("Export", selection: binding) {
            ForEach(ExportMode.allCases, id: \.self) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}

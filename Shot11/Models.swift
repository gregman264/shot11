import SwiftUI
import UIKit

struct CropBox {
    var x: CGFloat
    var y: CGFloat
    var side: CGFloat
}

enum Screen: Equatable {
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

struct StepDef {
    var file: String
    var title: String
    var short: String
    var symbol: String
    var caption: String = ""
    var crop: Bool = false
    var silhouette: Bool = false
    var auto: Bool = false
    var fx: CGFloat = 0
    var fy: CGFloat = 0
    var rotation: Double = 0
}

enum Steps {
    static let all: [StepDef] = [
        StepDef(file: "01_face.jpg", title: "Face", short: "Face", symbol: "tshirt",
                caption: "Vêtement entier, à plat, centré dans la silhouette.", crop: true, silhouette: true),
        StepDef(file: "02_zoom_haut_gauche.jpg", title: "Zoom haut gauche", short: "Haut gauche", symbol: "tshirt",
                auto: true, fx: 0, fy: 0),
        StepDef(file: "03_zoom_bas_gauche.jpg", title: "Zoom bas gauche", short: "Bas gauche", symbol: "tshirt",
                auto: true, fx: 0, fy: 1),
        StepDef(file: "04_zoom_bas_droit.jpg", title: "Zoom bas droit", short: "Bas droit", symbol: "tshirt",
                auto: true, fx: 1, fy: 1),
        StepDef(file: "05_zoom_haut_droit.jpg", title: "Zoom haut droit", short: "Haut droit", symbol: "tshirt",
                auto: true, fx: 1, fy: 0),
        StepDef(file: "06_etiquette_marque.jpg", title: "Étiquette marque", short: "Marque", symbol: "tag",
                caption: "Col ouvert : marque et taille bien lisibles."),
        StepDef(file: "07_etiquette_composition.jpg", title: "Étiquette composition", short: "Composition", symbol: "doc.text",
                caption: "Étiquette de composition, nette et lisible."),
        StepDef(file: "08_dos.jpg", title: "Dos", short: "Dos", symbol: "arrow.triangle.2.circlepath",
                caption: "Vêtement retourné, entier, centré dans la silhouette.", crop: true, silhouette: true),
        StepDef(file: "09_mesure_longueur.jpg", title: "Mesure longueur", short: "Longueur", symbol: "ruler",
                caption: "Mètre du col jusqu’en bas, bien droit.", rotation: 90),
        StepDef(file: "10_mesure_largeur.jpg", title: "Mesure largeur", short: "Largeur", symbol: "ruler",
                caption: "Mètre d’une aisselle à l’autre, à plat."),
        StepDef(file: "11_ref_stock.jpg", title: "Référence stock", short: "Réf. stock", symbol: "number",
                caption: "Étiquette de stock, bien lisible.")
    ]
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

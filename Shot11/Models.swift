import SwiftUI
import UIKit

struct CropBox {
    var x: CGFloat
    var y: CGFloat
    var side: CGFloat
}

/// Cadre de recadrage exprimé en fraction de l'image d'origine (indépendant de sa taille).
struct NBox: Codable {
    var x: Double
    var y: Double
    var side: Double
}

enum Screen: Equatable {
    case home
    case folder
    case start
    case camera
    case defect
    case adjust(Int)
    case recap
    case settings

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

enum ExportMode: String, CaseIterable {
    case folderPerRef
    case flat

    var label: String { self == .folderPerRef ? "Un dossier par réf" : "Un seul dossier" }
}

struct Folder: Codable, Identifiable {
    var id: String
    var name: String
    var created: Date
}

struct Article: Codable, Identifiable {
    var id: String
    var ref: String
    var kind: Garment
    var created: Date
    var wb: [Float]? = nil
    var boxes: [String: NBox]? = nil
    var defect: Bool? = nil        // nil = pas encore demandé, true = photo du défaut, false = aucun défaut
    var folderId: String? = nil
    var bg: Bool? = nil            // fond uniforme appliqué aux photos
    var ver: Int? = nil

    var needed: Int { defect == false ? 12 : 13 }
}

struct StepDef {
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
    static let count = 13
    static let defectIndex = 11
    static let skuIndex = 12

    static func isAuto(_ i: Int) -> Bool { i >= 1 && i <= 4 }

    /// Numéro de la photo dans le nom de fichier : sans photo de défaut, le SKU est la n°12.
    static func exportNumber(_ i: Int, defect: Bool?) -> Int {
        if i == skuIndex && defect != true { return 12 }
        return i + 1
    }

    static func defs(_ g: Garment) -> [StepDef] {
        let bottom = (g == .bottom)
        let sil = bottom ? 2 : 1
        let item = bottom ? "Pantalon" : "Vêtement"
        var a: [StepDef] = []
        a.append(StepDef(title: "Face", short: "Face", symbol: bottom ? "rectangle.portrait" : "tshirt",
                         caption: item + " entier, à plat, centré dans la silhouette.", crop: true, silhouette: sil))
        a.append(StepDef(title: "Zoom haut gauche", short: "Haut gauche", symbol: "tshirt", auto: true, fx: 0, fy: 0))
        a.append(StepDef(title: "Zoom bas gauche", short: "Bas gauche", symbol: "tshirt", auto: true, fx: 0, fy: 1))
        a.append(StepDef(title: "Zoom bas droit", short: "Bas droit", symbol: "tshirt", auto: true, fx: 1, fy: 1))
        a.append(StepDef(title: "Zoom haut droit", short: "Haut droit", symbol: "tshirt", auto: true, fx: 1, fy: 0))
        a.append(StepDef(title: "Logo", short: "Logo", symbol: "star.circle",
                         caption: "Logo de la marque, de près. Touche l’écran pour la netteté."))
        a.append(StepDef(title: "Étiquette marque", short: "Marque", symbol: "tag",
                         caption: bottom ? "Marque et taille bien lisibles (ceinture intérieure)." : "Col ouvert : marque et taille bien lisibles. Touche l’écran pour la netteté."))
        a.append(StepDef(title: "Étiquette composition", short: "Composition", symbol: "doc.text",
                         caption: "Étiquette de composition. Touche l’écran pour la netteté, ou zoome."))
        a.append(StepDef(title: "Dos", short: "Dos", symbol: bottom ? "rectangle.portrait" : "arrow.triangle.2.circlepath",
                         caption: item + " retourné, entier, centré dans la silhouette.", crop: true, silhouette: sil))
        a.append(StepDef(title: "Mesure longueur", short: "Longueur", symbol: "ruler",
                         caption: bottom ? "Mètre de la ceinture jusqu’au bas de la jambe, bien droit." : "Mètre du col jusqu’en bas, bien droit.",
                         rotation: 90))
        a.append(StepDef(title: "Mesure largeur", short: "Largeur", symbol: "ruler",
                         caption: bottom ? "Mètre sur la ceinture, d’un bord à l’autre, à plat." : "Mètre d’une aisselle à l’autre, à plat."))
        a.append(StepDef(title: "Défaut", short: "Défaut", symbol: "exclamationmark.triangle",
                         caption: "Le défaut (trou, tache, usure), de près. Touche l’écran pour la netteté."))
        a.append(StepDef(title: "Référence stock", short: "Réf. stock", symbol: "number",
                         caption: "Étiquette de stock, bien lisible."))
        return a
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
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
}

struct PrimaryButton: ButtonStyle {
    var ghost: Bool = false
    var height: CGFloat = 56
    var danger: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(ghost ? Theme.surface : Theme.accent)
            .foregroundColor(danger ? Theme.danger : (ghost ? Theme.fg : Color.white))
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

/// Fenêtre de partage iOS (enregistrer dans Fichiers, AirDrop, Photos…).
enum ShareSheet {
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        top.present(vc, animated: true)
    }
}

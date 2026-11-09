import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("bgEnabled") private var bgEnabled = false
    @AppStorage("bgUniformity") private var uniformity = 0.6
    @AppStorage("bgFixed") private var fixedColor = false
    @AppStorage("bgR") private var bgR = 0.20
    @AppStorage("bgG") private var bgG = 0.21
    @AppStorage("bgB") private var bgB = 0.23

    private var supported: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { store.screen = .home } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Articles")
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.accent)
                }
                Spacer()
            }
            .frame(height: 48)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Réglages")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.fg)

                    card {
                        Toggle(isOn: $bgEnabled) {
                            Text("Fond uniforme sur les nouveaux articles")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.fg)
                        }
                        .tint(Theme.accent)
                        .disabled(!supported)
                        Text(supported
                             ? "Le fond de chaque photo est remplacé par la même couleur, en plus uniforme, avec un peu de texture. Pour un article déjà pris : menu ⋯ de l’article."
                             : "Cette option demande iOS 17 ou plus.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(Theme.muted)
                    }

                    card {
                        Text("Uniformité du fond")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.fg)
                        HStack {
                            Text("Texture")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(Theme.muted)
                            Slider(value: $uniformity, in: 0.2...0.95)
                                .tint(Theme.accent)
                            Text("Uni")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(Theme.muted)
                        }
                    }

                    card {
                        Toggle(isOn: $fixedColor) {
                            Text("Même couleur sur toutes les photos")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.fg)
                        }
                        .tint(Theme.accent)
                        Text("Désactivé : chaque photo garde la couleur de son propre fond. Activé : tous les fonds prennent la couleur choisie.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(Theme.muted)
                        if fixedColor {
                            ColorPicker("Couleur du fond", selection: colorBinding, supportsOpacity: false)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.fg)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding<Color>(
            get: { Color(red: bgR, green: bgG, blue: bgB) },
            set: { c in
                var r: CGFloat = 0
                var g: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                if UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a) {
                    bgR = Double(r)
                    bgG = Double(g)
                    bgB = Double(b)
                }
            }
        )
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

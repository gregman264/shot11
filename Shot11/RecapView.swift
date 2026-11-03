import SwiftUI

/// Détail d'un article : toutes ses photos, avec possibilité de refaire chacune.
struct RecapView: View {
    @EnvironmentObject var store: Store
    @State private var confirmDelete = false

    private let cols = [GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(0..<11, id: \.self) { i in
                        cell(i)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                Text(missingText)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                if store.doneCount < 11 {
                    Button("Continuer les photos") { store.continueArticle() }
                        .buttonStyle(PrimaryButton())
                }
                ExportModePicker()
                exportButton
                Button("Supprimer cet article") { confirmDelete = true }
                    .buttonStyle(PrimaryButton(ghost: true, height: 44))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .alert("Supprimer l’article \(store.ref) ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { store.deleteCurrent() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ses photos seront effacées de l’appli.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.goHome() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Articles")
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.accent)
            }
            Spacer()
            Text(store.ref)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.fg)
                .lineLimit(1)
            Text("\(store.doneCount)/11")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .clipShape(Capsule())
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
    }

    private var missingText: String {
        let miss = 11 - store.doneCount
        if miss == 0 { return "Touche une photo pour la recadrer ou la refaire." }
        return "Il manque \(miss) photo" + (miss > 1 ? "s" : "") + ". Touche une vignette pour la prendre ou la recadrer."
    }

    @ViewBuilder
    private var exportButton: some View {
        if let url = store.zipURL {
            ShareLink(item: url) {
                Label("Partager / enregistrer le ZIP", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButton(ghost: store.doneCount < 11))
        } else {
            Button("Préparation du ZIP…") {}
                .buttonStyle(PrimaryButton(ghost: store.doneCount < 11))
                .disabled(true)
                .opacity(0.5)
        }
    }

    private func cell(_ i: Int) -> some View {
        Button { store.tapStep(i) } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Theme.surface
                    if let t = store.thumbs[i] {
                        Image(uiImage: t).resizable().scaledToFill()
                    } else {
                        Text("\(i + 1)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.muted)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("\(i + 1) · " + store.defs[i].short)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Détail d'un article : toutes ses photos, à recadrer ou à refaire.
struct RecapView: View {
    @EnvironmentObject var store: Store
    @State private var confirmDelete = false
    @State private var askRename = false
    @State private var text = ""

    private let cols = [GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(0..<Steps.count, id: \.self) { i in
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
                if store.nextTodo(from: -1) != nil {
                    Button("Continuer les photos") { store.continueArticle() }
                        .buttonStyle(PrimaryButton())
                }
                ExportModePicker()
                exportButton
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
        .alert("Renommer l’article", isPresented: $askRename) {
            TextField("Nouvelle référence", text: $text)
            Button("OK") { store.renameCurrent(text) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les photos exportées porteront ce nouveau nom.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.closeArticle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Retour")
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.accent)
            }
            Spacer()
            Text(store.ref)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.fg)
                .lineLimit(1)
            Text("\(store.doneCount)/\(store.requiredCount)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .clipShape(Capsule())
            Menu {
                Button("Renommer l’article") { text = store.ref; askRename = true }
                Button((store.current?.bg == true) ? "Retirer le fond uniforme" : "Appliquer le fond uniforme") {
                    store.setArticleBackground(store.current?.bg != true)
                }
                Button("Photos seules, sans ZIP") {
                    if let a = store.current {
                        store.exportFiles([ExportGroup(folder: nil, articles: [a])])
                    }
                }
                Button("Supprimer l’article", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Theme.muted)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
    }

    private var missingText: String {
        let miss = store.requiredCount - store.doneCount
        if miss <= 0 && store.nextTodo(from: -1) == nil { return "Touche une photo pour la recadrer ou la refaire." }
        if miss <= 0 { return "Il reste une question à valider. Touche « Continuer les photos »." }
        let plural = (miss > 1) ? "s" : ""
        return "Il manque \(miss) photo\(plural). Touche une vignette pour la prendre ou la recadrer."
    }

    @ViewBuilder
    private var exportButton: some View {
        let complete = store.nextTodo(from: -1) == nil
        if let url = store.zipURL {
            ShareLink(item: url) {
                Label("Partager / enregistrer le ZIP", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButton(ghost: !complete))
        } else {
            Button("Préparation du ZIP…") {}
                .buttonStyle(PrimaryButton(ghost: !complete))
                .disabled(true)
                .opacity(0.5)
        }
    }

    private func cell(_ i: Int) -> some View {
        let noDefect = (i == Steps.defectIndex && store.current?.defect == false && store.thumbs[i] == nil)
        return Button { store.tapStep(i) } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Theme.surface
                    if let t = store.thumbs[i] {
                        Image(uiImage: t).resizable().scaledToFill()
                    } else if noDefect {
                        Text("Aucun\ndéfaut")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("\(i + 1)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.muted)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(String(store.displayNumber(i)) + " · " + store.defs[i].short)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

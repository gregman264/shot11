import SwiftUI

struct RecapView: View {
    @EnvironmentObject var store: Store
    @State private var confirmNew = false

    private let cols = [GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Article " + store.ref)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text("\(store.doneCount)/11")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.surface)
                    .clipShape(Capsule())
            }
            .foregroundColor(Theme.fg)
            .frame(height: 48)
            .padding(.horizontal, 14)

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
                exportButton
                HStack(spacing: 10) {
                    Button("Retour caméra") {
                        if let n = store.nextTodo(from: -1) { store.enter(n) } else { store.enter(0) }
                    }
                    .buttonStyle(PrimaryButton(ghost: true, height: 46))
                    Button("Nouvel article") { confirmNew = true }
                        .buttonStyle(PrimaryButton(ghost: true, height: 46))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .alert("Effacer l’article \(store.ref) et recommencer ?", isPresented: $confirmNew) {
            Button("Effacer", role: .destructive) { store.newArticle() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var missingText: String {
        let miss = 11 - store.doneCount
        if miss == 0 { return "Tout est prêt. Touche une vignette pour refaire une photo." }
        return "Il manque \(miss) photo" + (miss > 1 ? "s" : "") + ". Touche une vignette pour la prendre ou la refaire."
    }

    @ViewBuilder
    private var exportButton: some View {
        if let url = store.zipURL {
            ShareLink(item: url) {
                Label("Partager / enregistrer le ZIP", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButton())
        } else {
            Button("Préparation du ZIP…") {}
                .buttonStyle(PrimaryButton())
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
                Text("\(i + 1) · " + Steps.all[i].short)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

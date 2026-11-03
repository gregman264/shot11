import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    Text("Shot").foregroundColor(Theme.fg)
                    Text("11").foregroundColor(Theme.accent)
                }
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                Spacer()
                Text(countText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)

            if store.articles.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.articles) { a in
                            row(a)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }

            VStack(spacing: 10) {
                Button("Nouvel article") { store.screen = .start }
                    .buttonStyle(PrimaryButton())
                if !store.articles.isEmpty {
                    ExportModePicker()
                    exportAll
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }

    private var countText: String {
        let n = store.articles.count
        return "\(n) article" + (n > 1 ? "s" : "")
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundColor(Theme.muted)
            Text("Aucun article pour l’instant.")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.fg)
            Text("Crée ton premier article pour lancer la séquence de 11 photos.")
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    private func row(_ a: Article) -> some View {
        let n = store.counts[a.id] ?? 0
        return Button { store.open(a) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Theme.line
                    if let c = store.covers[a.id] {
                        Image(uiImage: c).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo").foregroundColor(Theme.muted)
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(a.ref)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.fg)
                        .lineLimit(1)
                    Text(a.kind.label + " · " + String(n) + "/11 · " + a.created.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                if n >= 11 {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok)
                }
                Image(systemName: "chevron.right").foregroundColor(Theme.muted)
            }
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var exportAll: some View {
        if let url = store.allZipURL {
            ShareLink(item: url) {
                Label("Partager le ZIP de tous les articles", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButton(ghost: true, height: 50))
        } else {
            Button(store.allZipBuilding ? "Préparation du ZIP…" : "Exporter tous les articles") {
                store.prepareAllZip()
            }
            .buttonStyle(PrimaryButton(ghost: true, height: 50))
            .disabled(store.allZipBuilding)
        }
    }
}

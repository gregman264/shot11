import SwiftUI

/// Liste des articles et des dossiers (accueil) ou contenu d'un dossier.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    let folderId: String?

    @State private var askDelete = false
    @State private var askRename = false
    @State private var askNewFolder = false
    @State private var askRenameFolder = false
    @State private var askDeleteFolder = false
    @State private var text = ""

    private var isHome: Bool { folderId == nil }

    private var shownArticles: [Article] {
        store.inFolder(folderId)
    }

    private var shownFolders: [Folder] {
        isHome ? store.folders : []
    }

    private var allIds: Int {
        shownArticles.count + shownFolders.count
    }

    private var allSelected: Bool {
        allIds > 0 && store.selectionCount == allIds
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if store.selecting { selectionBar } else { normalBar }
        }
        .alert("Supprimer la sélection ?", isPresented: $askDelete) {
            Button("Supprimer", role: .destructive) { store.deleteSelected() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(store.deleteMessage)
        }
        .alert("Renommer", isPresented: $askRename) {
            TextField("Nouveau nom", text: $text)
            Button("OK") { store.renameSelected(text) }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Nouveau dossier", isPresented: $askNewFolder) {
            TextField("Nom du dossier", text: $text)
            Button("Créer") { store.createFolder(name: text, withSelection: store.selecting) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(store.selecting && !store.selectedArticles.isEmpty ? "Les articles sélectionnés seront rangés dedans." : "")
        }
        .alert("Renommer le dossier", isPresented: $askRenameFolder) {
            TextField("Nouveau nom", text: $text)
            Button("OK") { if let id = folderId { store.renameFolder(id, text) } }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Supprimer ce dossier ?", isPresented: $askDeleteFolder) {
            Button("Supprimer le dossier", role: .destructive) {
                if let id = folderId { store.deleteFolder(id); store.closeFolder() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les articles qu’il contient sont conservés.")
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if isHome {
                HStack(spacing: 0) {
                    Text("Shot").foregroundColor(Theme.fg)
                    Text("11").foregroundColor(Theme.accent)
                }
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            } else {
                Button { store.closeFolder() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Articles")
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.accent)
                }
                Text(store.folderName(folderId))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.fg)
                    .lineLimit(1)
            }
            Spacer()
            if !store.selecting {
                if isHome {
                    Button { store.screen = .settings } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Theme.muted)
                    }
                } else {
                    Menu {
                        Button("Renommer le dossier") { text = store.folderName(folderId); askRenameFolder = true }
                        Button("Supprimer le dossier", role: .destructive) { askDeleteFolder = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Theme.muted)
                    }
                }
                if allIds > 0 {
                    Button("Sélectionner") { store.startSelecting() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.accent)
                }
            } else {
                Text(selectionText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.muted)
                Button("Terminer") { store.stopSelecting() }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var selectionText: String {
        let n = store.selectionCount
        return n == 0 ? "Aucune sélection" : "\(n) sélectionné" + (n > 1 ? "s" : "")
    }

    // MARK: Liste

    @ViewBuilder
    private var content: some View {
        if shownArticles.isEmpty && shownFolders.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.muted)
                Text(isHome ? "Aucun article pour l’instant." : "Ce dossier est vide.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.fg)
                Text("Crée un article pour lancer la séquence de photos.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 30)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(shownFolders) { f in
                        folderRow(f)
                    }
                    if !shownFolders.isEmpty && !shownArticles.isEmpty {
                        Text("Articles sans dossier")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                            .padding(.horizontal, 6)
                    }
                    ForEach(shownArticles) { a in
                        articleRow(a)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func checkmark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24))
            .foregroundColor(on ? Theme.accent : Theme.muted)
    }

    private func folderRow(_ f: Folder) -> some View {
        let n = store.inFolder(f.id).count
        let on = store.selectedFolders.contains(f.id)
        return Button {
            if store.selecting { store.toggleFolder(f.id) } else { store.openFolder(f.id) }
        } label: {
            HStack(spacing: 14) {
                if store.selecting { checkmark(on) }
                ZStack {
                    Theme.line
                    Image(systemName: "folder.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.accent)
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.name)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.fg)
                        .lineLimit(1)
                    Text("\(n) article" + (n > 1 ? "s" : ""))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                if !store.selecting {
                    Image(systemName: "chevron.right").foregroundColor(Theme.muted)
                }
            }
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func articleRow(_ a: Article) -> some View {
        let n = store.counts[a.id] ?? 0
        let on = store.selectedArticles.contains(a.id)
        let date = a.created.formatted(.dateTime.day().month(.abbreviated))
        let sub = a.kind.label + " · " + String(n) + "/" + String(a.needed) + " · " + date
        return Button {
            if store.selecting { store.toggleArticle(a.id) } else { store.open(a) }
        } label: {
            HStack(spacing: 14) {
                if store.selecting { checkmark(on) }
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
                    Text(sub)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                if n >= a.needed && a.defect != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok)
                }
                if !store.selecting {
                    Image(systemName: "chevron.right").foregroundColor(Theme.muted)
                }
            }
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Barres du bas

    private var normalBar: some View {
        VStack(spacing: 10) {
            Button("Nouvel article") {
                store.backTarget = isHome ? .home : .folder
                store.screen = .start
            }
            .buttonStyle(PrimaryButton())
            if isHome {
                Button("Nouveau dossier") { text = ""; askNewFolder = true }
                    .buttonStyle(PrimaryButton(ghost: true, height: 46))
            }
            if !shownArticles.isEmpty || !shownFolders.isEmpty {
                ExportModePicker()
                exportMenu
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var exportMenu: some View {
        Menu {
            Button(isHome ? "Tout exporter en ZIP" : "Exporter ce dossier en ZIP") {
                if isHome {
                    store.exportZip(store.allGroups(), name: "Shot11_tout")
                } else if let id = folderId {
                    store.exportZip(store.folderGroups(id), name: store.folderName(id))
                }
            }
            Button(isHome ? "Tout exporter sans ZIP (photos)" : "Exporter ce dossier sans ZIP (photos)") {
                if isHome {
                    store.exportFiles(store.allGroups())
                } else if let id = folderId {
                    store.exportFiles(store.folderGroups(id))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text(isHome ? "Tout exporter" : "Exporter ce dossier")
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(Theme.fg)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button(allSelected ? "Aucun" : "Tout") { toggleAll() }
                .buttonStyle(PrimaryButton(ghost: true, height: 50))
            Menu {
                Button("Créer un dossier avec la sélection") { text = ""; askNewFolder = true }
                    .disabled(store.selectedArticles.isEmpty)
                Menu("Ranger dans un dossier") {
                    ForEach(store.folders) { f in
                        Button(f.name) { store.moveSelected(to: f.id) }
                    }
                }
                .disabled(store.selectedArticles.isEmpty || store.folders.isEmpty)
                Button("Sortir du dossier") { store.moveSelected(to: nil) }
                    .disabled(store.selectedArticles.isEmpty || isHome)
                Button("Renommer") { text = ""; askRename = true }
                    .disabled(!store.canRenameSelection())
                Button("Exporter en ZIP") { store.exportZip(store.selectionGroups(), name: "Shot11_selection") }
                    .disabled(store.selectionCount == 0)
                Button("Exporter sans ZIP (photos)") { store.exportFiles(store.selectionGroups()) }
                    .disabled(store.selectionCount == 0)
            } label: {
                Text("Actions")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.fg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Button("Supprimer") { askDelete = true }
                .buttonStyle(PrimaryButton(ghost: true, height: 50, danger: true))
                .disabled(store.selectionCount == 0)
                .opacity(store.selectionCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func toggleAll() {
        if allSelected {
            store.selectedArticles = []
            store.selectedFolders = []
        } else {
            store.selectedArticles = Set(shownArticles.map { $0.id })
            store.selectedFolders = Set(shownFolders.map { $0.id })
        }
    }
}

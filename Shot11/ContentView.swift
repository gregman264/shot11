import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var cam: CameraService

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            screenView
            busyView
            toastView
        }
        .preferredColorScheme(.dark)
        .onChange(of: store.screen) { s in
            if s == .camera, let wb = store.current?.wb { cam.useGains(wb) }
            if s.usesCamera { cam.start() } else { cam.stop() }
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch store.screen {
        case .home:
            LibraryView(folderId: nil)
        case .folder:
            LibraryView(folderId: store.currentFolderId)
        case .start:
            StartView()
        case .camera:
            CameraView()
        case .defect:
            DefectView()
        case .adjust(let i):
            AdjustView(idx: i)
        case .recap:
            RecapView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var busyView: some View {
        if store.busy || store.processing != nil || store.exporting {
            VStack {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.fg)
                    Text(store.processing ?? (store.exporting ? "Préparation de l’export…" : "Traitement…"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.fg)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .clipShape(Capsule())
                .padding(.top, 8)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = store.toast {
            VStack {
                Spacer()
                Text(t)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.bg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Theme.fg)
                    .clipShape(Capsule())
                    .padding(.bottom, 130)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

struct TopBar: View {
    let number: Int
    let total: Int
    let title: String
    let ref: String

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(number)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("/\(total)")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Theme.muted)
            }
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()
            Text(ref)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .clipShape(Capsule())
        }
        .foregroundColor(Theme.fg)
        .frame(height: 48)
        .padding(.horizontal, 14)
    }
}

import SwiftUI

struct Silhouette: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [CGPoint] = [
            CGPoint(x: 38, y: 17), CGPoint(x: 62, y: 17), CGPoint(x: 64, y: 24), CGPoint(x: 76, y: 28),
            CGPoint(x: 93, y: 53), CGPoint(x: 86, y: 71), CGPoint(x: 74, y: 65), CGPoint(x: 72, y: 55),
            CGPoint(x: 70, y: 83), CGPoint(x: 30, y: 83), CGPoint(x: 28, y: 55), CGPoint(x: 26, y: 65),
            CGPoint(x: 14, y: 71), CGPoint(x: 7, y: 53), CGPoint(x: 24, y: 28), CGPoint(x: 36, y: 24)
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let q = CGPoint(x: r.minX + pt.x / 100 * r.width, y: r.minY + pt.y / 100 * r.height)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

struct Guides: View {
    let silhouette: Bool

    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .padding(s * 0.06)
                Path { p in
                    p.move(to: CGPoint(x: s / 2, y: s * 0.44))
                    p.addLine(to: CGPoint(x: s / 2, y: s * 0.56))
                    p.move(to: CGPoint(x: s * 0.44, y: s / 2))
                    p.addLine(to: CGPoint(x: s * 0.56, y: s / 2))
                }
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if silhouette {
                    Silhouette()
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [7, 5]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CameraView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var cam: CameraService
    @State private var hintMode = 0      // 0 = plein, 1 = discret, 2 = caché
    @State private var flashOn = false
    @State private var hintWork: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 28, geo.size.height - 300))
            VStack(spacing: 0) {
                TopBar(number: store.step + 1, title: Steps.all[store.step].title, ref: store.ref)
                viewfinder(side: side)
                    .padding(.top, 6)
                Text(Steps.all[store.step].caption)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(height: 44)
                    .padding(.horizontal, 20)
                controls
                strip
                    .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { showHint() }
        .onChange(of: store.step) { _ in showHint() }
    }

    // MARK: Viseur

    private func viewfinder(side: CGFloat) -> some View {
        let def = Steps.all[store.step]
        return ZStack {
            Color.black
            CameraPreview(session: cam.session)
            Guides(silhouette: def.silhouette)
            hintView(def)
            Color.white.opacity(flashOn ? 0.85 : 0).allowsHitTesting(false)
            if !cam.authorized { deniedView }
            VStack {
                HStack {
                    wbBadge
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var wbBadge: some View {
        Button {
            cam.recalibrateWhiteBalance()
            store.showToast("Mesure du blanc… elle se verrouille seule")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cam.whiteBalanceLocked ? "lock.fill" : "lock.open")
                Text(cam.whiteBalanceLocked ? "Blancs verrouillés" : "Mesure du blanc…")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
        }
    }

    private func hintView(_ def: StepDef) -> some View {
        VStack(spacing: 10) {
            Image(systemName: def.symbol)
                .font(.system(size: 64, weight: .semibold))
                .rotationEffect(.degrees(def.rotation))
            Text(def.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .shadow(color: Color.black.opacity(0.7), radius: 6)
        .scaleEffect(hintMode == 0 ? 1 : (hintMode == 1 ? 0.7 : 0.6))
        .opacity(hintMode == 0 ? 1 : (hintMode == 1 ? 0.32 : 0))
        .animation(.easeInOut(duration: 0.35), value: hintMode)
        .allowsHitTesting(false)
    }

    private var deniedView: some View {
        VStack(spacing: 14) {
            Text("Caméra refusée. Autorise-la dans Réglages, puis reviens ici.")
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.fg)
            Button("Ouvrir les réglages") {
                if let u = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(u)
                }
            }
            .buttonStyle(PrimaryButton(height: 46))
            .frame(width: 220)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    // MARK: Commandes

    private var controls: some View {
        HStack {
            sideButton(title: "Refaire", symbol: "arrow.counterclockwise") { store.previousPhoto() }
            Spacer()
            Button(action: shoot) {
                ZStack {
                    Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 80, height: 80)
                    Circle().fill(Color.white).frame(width: 62, height: 62)
                }
            }
            .buttonStyle(.plain)
            .disabled(store.busy || !cam.running)
            .opacity((store.busy || !cam.running) ? 0.4 : 1)
            Spacer()
            sideButton(title: "Récap", symbol: "square.grid.2x2") { store.goRecap() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func sideButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Theme.fg)
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }

    private var strip: some View {
        HStack(spacing: 3) {
            ForEach(0..<11, id: \.self) { i in
                Button { store.tapStep(i) } label: {
                    ZStack {
                        Theme.surface
                        if let t = store.thumbs[i] {
                            Image(uiImage: t).resizable().scaledToFill()
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(i == store.step ? Theme.accent : Color.clear, lineWidth: 2)
                    )
                    .opacity((Steps.all[i].auto && store.thumbs[i] == nil) ? 0.45 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Actions

    private func shoot() {
        if store.busy { return }
        flashOn = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.2)) { flashOn = false }
        }
        hintWork?.cancel()
        hintMode = 2
        store.busy = true
        cam.capture { data in
            if let d = data {
                store.handleCapture(d)
            } else {
                store.busy = false
                store.showToast("La photo a échoué, réessaie")
            }
        }
    }

    private func showHint() {
        hintWork?.cancel()
        hintMode = 0
        let w = DispatchWorkItem { hintMode = 1 }
        hintWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: w)
    }
}

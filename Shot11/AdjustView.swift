import SwiftUI

struct AdjustView: View {
    @EnvironmentObject var store: Store
    let idx: Int
    @State private var dragBase: CropBox? = nil
    @State private var pinchBase: CGFloat? = nil

    private var isAuto: Bool { Steps.isAuto(idx) }

    var body: some View {
        GeometryReader { geo in
            let extra: CGFloat = (idx == 0) ? 50 : 0
            let side = max(200, min(geo.size.width - 28, geo.size.height - 290 - extra))
            VStack(spacing: 0) {
                TopBar(number: store.displayNumber(idx), total: store.requiredCount, title: "Cadrage · " + store.defs[idx].title, ref: store.ref)
                stage(side: side)
                    .padding(.top, 6)
                Text(helpText)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(height: 44)
                    .padding(.horizontal, 20)
                sizeSlider
                if idx == 0 {
                    Toggle(isOn: $store.regenZooms) {
                        Text("Recalculer les 4 zooms de coin")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.fg)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
                buttons
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var helpText: String {
        if isAuto { return "Ce zoom se recadre seul : déplace le cadre, pince pour zoomer." }
        if idx == 0 { return "Déplace le cadre, pince pour zoomer. Les 4 zooms de coin en seront tirés." }
        return "Déplace le cadre, pince pour zoomer."
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("Annuler") { store.cancelAdjust() }
                .buttonStyle(PrimaryButton(ghost: true))
            if !isAuto {
                Button("Refaire") { store.retake(idx) }
                    .buttonStyle(PrimaryButton(ghost: true))
            }
            Button("Valider") { store.validateAdjust(idx) }
                .buttonStyle(PrimaryButton())
                .disabled(store.busy)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func stage(side: CGFloat) -> some View {
        let src = store.sources[store.srcIndex(idx)]
        let S: CGFloat = src?.size.width ?? 1
        let k = side / S
        let b = store.adjustBox
        let rect = CGRect(x: b.x * k, y: b.y * k, width: b.side * k, height: b.side * k)
        return ZStack(alignment: .topLeading) {
            Color.black
            if let img = src {
                Image(uiImage: img).resizable().frame(width: side, height: side)
            }
            Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: side, height: side))
                p.addRect(rect)
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    if dragBase == nil { dragBase = store.adjustBox }
                    guard let base = dragBase else { return }
                    let nx = min(max(base.x + v.translation.width / k, 0), S - base.side)
                    let ny = min(max(base.y + v.translation.height / k, 0), S - base.side)
                    store.adjustBox = CropBox(x: nx, y: ny, side: base.side)
                }
                .onEnded { _ in dragBase = nil }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { m in
                    if pinchBase == nil { pinchBase = store.adjustBox.side }
                    let base = pinchBase ?? store.adjustBox.side
                    store.setSide(base / max(m, 0.1), S: S)
                }
                .onEnded { _ in pinchBase = nil }
        )
    }

    private var sizeSlider: some View {
        let S: CGFloat = store.sources[store.srcIndex(idx)]?.size.width ?? 1
        let binding = Binding<Double>(
            get: { Double(store.adjustBox.side / S) },
            set: { store.setSide(S * CGFloat($0), S: S) }
        )
        return HStack(spacing: 12) {
            Text("Cadre")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.muted)
            Slider(value: binding, in: 0.2...1.0)
                .tint(Theme.accent)
            Button("Auto") { store.resetBox(idx) }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }
}

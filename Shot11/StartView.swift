import SwiftUI

struct StartView: View {
    @EnvironmentObject var store: Store
    @State private var ref: String = ""
    @State private var kind: Garment = .top
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.screen = .home
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Articles")
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.accent)
            }
            .padding(.top, 14)

            Spacer()

            Text("Nouvel article")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.bottom, 30)

            Text("Référence de l’article")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.bottom, 8)

            TextField("T488", text: $ref)
                .focused($focused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .onSubmit { focused = false }
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("Type de vêtement")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Picker("Type", selection: $kind) {
                ForEach(Garment.allCases, id: \.self) { g in
                    Text(g.label).tag(g)
                }
            }
            .pickerStyle(.segmented)

            Button("Commencer") { go() }
                .buttonStyle(PrimaryButton())
                .padding(.top, 24)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            if ref.isEmpty { ref = store.suggestedRef }
        }
    }

    private func go() {
        focused = false
        store.createArticle(ref: ref, kind: kind)
        ref = ""
    }
}

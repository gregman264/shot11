import SwiftUI

struct StartView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var cam: CameraService
    @State private var ref: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Text("Shot").foregroundColor(Theme.fg)
                Text("11").foregroundColor(Theme.accent)
            }
            .font(.system(size: 64, weight: .heavy, design: .rounded))

            Text("Onze photos, toujours dans le même ordre, recadrées toutes seules.")
                .font(.system(size: 18, design: .rounded))
                .foregroundColor(Theme.muted)
                .padding(.top, 12)
                .padding(.bottom, 34)

            Text("Référence de l’article")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.bottom, 8)

            TextField("T488", text: $ref)
                .focused($focused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .submitLabel(.go)
                .onSubmit { go() }
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.fg)
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Button("Commencer") { go() }
                .buttonStyle(PrimaryButton())
                .padding(.top, 14)

            if let info = store.resumeInfo {
                VStack(alignment: .leading, spacing: 10) {
                    Text(info)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(Theme.muted)
                    Button("Reprendre") {
                        cam.restoreSavedGains()
                        store.resume()
                    }
                    .buttonStyle(PrimaryButton(ghost: true, height: 46))
                }
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.top, 22)
            }

            Spacer()
            Text("Tout reste sur ton iPhone. Aucune photo n’est envoyée.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .onAppear {
            if ref.isEmpty { ref = store.suggestedRef }
            store.refreshResumeInfo()
        }
    }

    private func go() {
        focused = false
        store.startSession(ref: ref)
    }
}

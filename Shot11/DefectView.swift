import SwiftUI

/// Juste avant la photo du SKU : y a-t-il un défaut à photographier ?
struct DefectView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(number: store.displayNumber(Steps.defectIndex), total: store.requiredCount, title: "Défaut ?", ref: store.ref)
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(Theme.accent)
                .padding(.bottom, 18)
            Text("Y a-t-il un défaut ?")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.fg)
            Text("Trou, tache, bouloche, usure… Si oui, tu le photographies de près avant la photo du SKU.")
                .font(.system(size: 17, design: .rounded))
                .foregroundColor(Theme.muted)
                .padding(.top, 10)
                .padding(.bottom, 30)
            Button("Oui, photographier le défaut") { store.chooseDefect(true) }
                .buttonStyle(PrimaryButton())
            Button("Non, passer au SKU") { store.chooseDefect(false) }
                .buttonStyle(PrimaryButton(ghost: true))
                .padding(.top, 10)
            Spacer()
            Button("Retour à l’article") { store.cancelDefect() }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }
}

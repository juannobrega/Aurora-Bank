import SwiftUI

/// Entrada por PIN real (Keychain) ou biometria de verdade.
struct LockScreenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Text(model.user.initials.isEmpty ? "A" : model.user.initials)
                    .font(.display(20, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Theme.cyan, in: .circle)
                Text(model.user.name.isEmpty ? "Bem-vindo" : "Olá, \(model.user.firstName)")
                    .font(.auroraTitle)
                    .foregroundStyle(Theme.text)
            }
            Spacer()

            PinAuthorizationView(
                title: "",
                subtitle: "Digite seu PIN de 4 dígitos",
                allowsBiometrics: model.settings.biometricsEnabled
            ) {
                model.unlock()
            }
            .frame(maxHeight: 460)

            Button {
                model.showToast("Enviamos um link de recuperação para seu e-mail")
            } label: {
                Text("Esqueci o PIN")
                    .font(.auroraLabel)
                    .foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .auroraBackground(horizon: true)
    }
}

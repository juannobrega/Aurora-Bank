import SwiftUI

/// Entrada da conta. O PIN é validado localmente (Keychain) e, quando o
/// backend é remoto, também autentica na API para obter a sessão — só então
/// entra. Assim o desbloqueio e o login no servidor acontecem no mesmo gesto.
struct LockScreenView: View {
    @Environment(AppModel.self) private var model
    @State private var authenticating = false
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Text(model.user.initials.isEmpty ? "A" : model.user.initials)
                    .font(.display(20, .medium))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Theme.actionGradient, in: .circle)
                Text(greeting).font(.auroraTitle).foregroundStyle(Theme.text)
            }
            Spacer()

            if authenticating {
                VStack(spacing: 14) {
                    OrbitLoader(size: 44)
                    Text("Entrando…").font(.auroraBody).foregroundStyle(Theme.text2)
                }
                .frame(maxHeight: 460)
            } else {
                PinAuthorizationView(
                    title: "",
                    subtitle: authError ?? "Digite seu PIN de 4 dígitos",
                    subtitleIsError: authError != nil,
                    allowsBiometrics: model.settings.biometricsEnabled,
                    verifyLocally: !model.usesRemoteBackend
                ) { pin in
                    Task { await enter(pin: pin) }
                }
                .frame(maxHeight: 460)
            }

            Button {
                model.showToast("Enviamos um link de recuperação para seu e-mail")
            } label: {
                Text("Esqueci o PIN").font(.auroraLabel).foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .auroraBackground(horizon: true)
    }

    private var greeting: String {
        model.user.name.isEmpty ? "Bem-vindo" : "Olá, \(model.user.firstName)"
    }

    /// Valida o PIN e, se remoto, autentica na API antes de abrir a home.
    private func enter(pin: String) async {
        authError = nil
        if model.usesRemoteBackend {
            guard let cpf = model.rememberedCpf else {
                authError = "Conta não encontrada neste aparelho."
                return
            }
            authenticating = true
            do {
                try await model.remoteLoginPin(cpf: cpf, pin: pin)
                model.unlock()
            } catch {
                authenticating = false
                authError = (error as? APIError)?.message ?? "PIN incorreto."
                Haptics.error()
            }
        } else {
            // Mock: o PIN já foi validado localmente pelo PinAuthorizationView.
            model.unlock()
        }
    }
}

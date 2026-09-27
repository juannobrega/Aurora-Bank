import SwiftUI

/// Login de quem já tem conta neste aparelho novo (ou reinstalou): pede CPF
/// e PIN e autentica na API. Diferente da tela de bloqueio, que já sabe o CPF
/// lembrado — aqui o usuário se identifica do zero.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var cpf = ""
    @State private var pin = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var cpfFocused: Bool

    private var canSubmit: Bool { CPF.isValid(cpf) && pin.count == 4 }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Entrar")
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        AuroraMark(width: 72)
                        Text("Bom te ver de novo")
                            .font(.auroraHeadline).foregroundStyle(Theme.text)
                    }
                    .padding(.top, 12)

                    field("CPF") {
                        TextField("000.000.000-00", text: $cpf)
                            .keyboardType(.numberPad)
                            .focused($cpfFocused)
                            .onChange(of: cpf) { _, v in cpf = CPF.mask(v) }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PIN").font(.auroraLabel).foregroundStyle(Theme.text2)
                        PinDots(filled: pin.count, isError: error != nil)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        Keypad { key in
                            switch key {
                            case .digit(let d): if pin.count < 4 { error = nil; pin += d }
                            case .delete: error = nil; _ = pin.popLast()
                            default: break
                            }
                        }
                    }

                    if let error {
                        Text(error).font(.auroraCaption).foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.Space.gutter)
            }

            PrimaryButton(title: busy ? "Entrando…" : "Entrar", enabled: canSubmit && !busy) {
                Task { await submit() }
            }
            .padding(Theme.Space.gutter)
        }
        .auroraBackground(horizon: true)
        .navigationBarBackButtonHidden()
        .onAppear { cpfFocused = true }
    }

    private func submit() async {
        busy = true; error = nil
        do {
            try await model.remoteLoginPin(cpf: CPF.digits(cpf), pin: pin)
            model.rememberIdentity(name: model.user.name.isEmpty ? "" : model.user.name,
                                   cpf: CPF.digits(cpf), email: model.user.email)
            // Guarda o PIN local para os próximos desbloqueios e autorizações.
            try? model.security.setPIN(pin)
            model.unlock()
        } catch let err {
            busy = false
            error = (err as? APIError)?.message ?? "CPF ou PIN incorretos."
            pin = ""
            Haptics.error()
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.auroraLabel).foregroundStyle(Theme.text2)
            content()
                .font(.auroraBody).foregroundStyle(Theme.text)
                .padding(16)
                .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon)
                    .stroke(Theme.line, lineWidth: 1))
        }
    }
}

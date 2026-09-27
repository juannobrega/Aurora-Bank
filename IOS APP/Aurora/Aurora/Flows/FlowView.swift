import SwiftUI

/// Container do motor de fluxo: desenha o passo corrente e cuida da
/// navegação entre eles. Toda a UI de Pix, investir, guardar, boleto,
/// recarga e empréstimo passa por aqui.
struct FlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: FlowSession

    init(flow: any TransactionFlow, startAt: FlowStep? = nil) {
        _session = State(initialValue: FlowSession(flow: flow, startAt: startAt))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch session.step {
                case .recipient: recipientStep
                case .amount:    amountStep
                case .confirm:   confirmStep
                case .pin:       pinStep
                case .done:      doneStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
        }
        .animation(.snappy(duration: 0.28), value: session.step)
        .auroraBackground(horizon: true)
        .navigationBarBackButtonHidden()
        .interactiveDismissDisabled(session.step == .done)
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: 12) {
            if session.canGoBack {
                Button {
                    if !session.retreat() { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 38)
                        .background(Theme.surface1, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar")
            } else {
                Color.clear.frame(width: 38, height: 38)
            }
            Text(session.flow.title).font(.auroraHeadline).foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 12)
    }

    // MARK: Passo 1 — destinatário

    @ViewBuilder
    private var recipientStep: some View {
        switch session.flow {
        case let pix as PixFlow:
            PixRecipientStep(session: session, flow: pix)
        case let boleto as BoletoFlow:
            BoletoScanStep(session: session, flow: boleto)
        case let recarga as RecargaFlow:
            RecargaPhoneStep(session: session, flow: recarga)
        default:
            EmptyStateView(symbol: "questionmark.circle", title: "Passo indisponível")
        }
    }

    // MARK: Passo 2 — valor

    private var amountStep: some View {
        let validation = session.flow.validate(entered: session.entered, context: model.flowContext)
        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(session.flow.amountPrompt)
                    .font(.auroraBody).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                Text(session.entered.formatted)
                    .font(.mono(38, .semibold))
                    .foregroundStyle(session.entered.isZero ? Theme.text3 : Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: session.centsText)
                Text(validation.hint)
                    .font(.auroraCaption)
                    .foregroundStyle(validation.isWarning ? Theme.danger : Theme.text2)
                    .frame(height: 18)
            }
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)

            if let recarga = session.flow as? RecargaFlow {
                RecargaPresets(session: session)
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, 16)
                let _ = recarga
            }

            Keypad { key in
                switch key {
                case .digit(let d): session.appendDigit(d)
                case .delete: session.deleteDigit()
                default: break
                }
            }
            .padding(.horizontal, Theme.Space.gutter)

            PrimaryButton(title: "Continuar", enabled: validation.isValid) {
                session.advance()
            }
            .padding(Theme.Space.gutter)
        }
    }

    // MARK: Passo 3 — revisão

    private var confirmStep: some View {
        let shown = session.flow.displayAmount(entered: session.entered)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text(session.flow.confirmPrompt)
                            .font(.auroraBody).foregroundStyle(Theme.text2)
                        Text(shown.formatted)
                            .font(.auroraValue).foregroundStyle(Theme.text)
                    }
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)

                    AuroraCard {
                        let rows = session.flow.rows(entered: session.entered, context: model.flowContext)
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                DetailRow(label: row.label, value: row.value,
                                          showsDivider: i < rows.count - 1)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                }
            }
            // Fluxos sem passo de valor (boleto, empréstimo) só passam por
            // aqui — sem consultar a validação, um boleto acima do saldo
            // seguiria adiante e deixaria a conta negativa.
            let check = session.flow.validate(entered: session.entered,
                                              context: model.flowContext)
            PrimaryButton(title: session.flow.confirmCallToAction,
                          enabled: check.isValid) {
                session.advance()
            }
            .padding(Theme.Space.gutter)
            if !check.isValid, !check.hint.isEmpty {
                Text(check.hint)
                    .font(.auroraCaption).foregroundStyle(Theme.danger)
                    .padding(.bottom, Theme.Space.md)
            }
        }
    }

    // MARK: Passo 4 — PIN

    private var pinStep: some View {
        let shown = session.flow.displayAmount(entered: session.entered)
        return PinAuthorizationView(
            title: "Digite seu PIN",
            subtitle: "Para autorizar \(shown.formatted)",
            allowsBiometrics: model.settings.biometricsEnabled
        ) { _ in
            commit()
        }
    }

    // MARK: Passo 5 — comprovante

    @ViewBuilder
    private var doneStep: some View {
        if let result = session.result {
            ReceiptView(
                result: result,
                rows: session.flow.rows(entered: session.entered, context: model.flowContext),
                amount: session.flow.displayAmount(entered: session.entered)
            ) {
                dismiss()
            }
        } else {
            ProgressView().tint(Theme.cyan).frame(maxHeight: .infinity)
        }
    }

    private func commit() {
        let result = session.flow.commit(entered: session.entered, model: model)
        session.result = result
        Haptics.success()
        session.advance()
    }
}

// MARK: - Tela de PIN reutilizável

struct PinAuthorizationView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    var subtitleIsError = false
    var allowsBiometrics = true
    /// Quando true, valida o PIN no Keychain antes de chamar o callback
    /// (fluxos de transação). Quando false, apenas repassa o PIN — quem
    /// chama valida (login remoto, que confere na API).
    var verifyLocally = true
    var onSuccess: (String) -> Void

    /// Conveniência para quem não precisa do PIN digitado.
    init(title: String, subtitle: String, subtitleIsError: Bool = false,
         allowsBiometrics: Bool = true, verifyLocally: Bool = true,
         onSuccess: @escaping (String) -> Void) {
        self.title = title; self.subtitle = subtitle
        self.subtitleIsError = subtitleIsError
        self.allowsBiometrics = allowsBiometrics
        self.verifyLocally = verifyLocally
        self.onSuccess = onSuccess
    }

    @State private var pin = ""
    @State private var isError = false
    @State private var attempts = 0
    @State private var biometricsTried = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Text(title).font(.auroraHeadline).foregroundStyle(Theme.text)
                Text(isError ? "PIN incorreto. Tente de novo." : subtitle)
                    .font(.auroraBody)
                    .foregroundStyle(isError || subtitleIsError ? Theme.danger : Theme.text2)
                    .multilineTextAlignment(.center)
                PinDots(filled: pin.count, isError: isError).padding(.top, 8)
            }
            .frame(maxHeight: .infinity)

            Keypad(showsBiometry: allowsBiometrics && model.security.hasPIN()) { key in
                switch key {
                case .digit(let d): append(d)
                case .delete:
                    isError = false
                    _ = pin.popLast()
                case .biometry: Task { await biometricAuth() }
                default: break
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.gutter)
        }
        .task {
            // Uma única tentativa automática. Sem a guarda, uma falha volta
            // para esta view, o .task roda de novo e o Face ID entra em loop.
            guard !biometricsTried else { return }
            biometricsTried = true
            if allowsBiometrics, model.settings.biometricsEnabled, model.security.hasPIN() {
                await biometricAuth()
            }
        }
    }

    private func append(_ d: String) {
        guard pin.count < 4 else { return }
        isError = false
        pin += d
        guard pin.count == 4 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            verify()
        }
    }

    private func verify() {
        if !verifyLocally {
            let entered = pin; pin = ""; onSuccess(entered); return
        }
        if model.security.verifyPIN(pin) {
            onSuccess(pin)
        } else {
            attempts += 1
            Haptics.error()
            withAnimation(.snappy(duration: 0.3)) { isError = true }
            pin = ""
            if attempts >= 3 {
                model.showToast("Muitas tentativas. Use Face ID ou recupere seu PIN.")
                attempts = 0
            }
        }
    }

    private func biometricAuth() async {
        do {
            let ok = try await model.security.authenticateWithBiometrics(
                reason: subtitle.isEmpty ? "Autorize para continuar" : subtitle
            )
            if ok { onSuccess("") }
        } catch {
            // Usuário cancelou ou biometria indisponível: segue pelo PIN.
        }
    }
}

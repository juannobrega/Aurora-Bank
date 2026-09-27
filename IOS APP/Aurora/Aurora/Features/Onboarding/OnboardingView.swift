import SwiftUI

/// Abertura de conta. Diferente do protótipo, termina **criando um PIN real**
/// guardado no Keychain — lá o onboarding acabava sem nunca definir PIN,
/// e o login aceitava qualquer sequência de 4 dígitos.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable { case identity, liveness, account, pin }

    @State private var step: Step = .identity
    @State private var name = ""
    @State private var cpf = ""
    @State private var email = ""
    @State private var liveness: Liveness = .idle
    @State private var faceTemplate: [Float]?
    @State private var showCamera = false
    @State private var submitting = false
    @State private var submitError: String?
    @State private var accountKind = "digital"
    @State private var acceptedTerms = false
    @State private var pin = ""
    @State private var pinConfirm = ""
    @State private var pinError: String?
    @FocusState private var focusedField: Field?

    enum Liveness { case idle, scanning, done }
    enum Field: Hashable { case nome, cpf, email }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBars
            ScrollView {
                Group {
                    switch step {
                    case .identity: identityStep
                    case .liveness: livenessStep
                    case .account:  accountStep
                    case .pin:      pinStep
                    }
                }
                .padding(Theme.Space.gutter)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: ctaTitle, enabled: canAdvance, action: advance)
                .padding(Theme.Space.gutter)
                .accessibilityIdentifier("onboardingCTA")
        }
        .animation(.snappy(duration: 0.26), value: step)
        .auroraBackground()
        .fullScreenCover(isPresented: $showCamera) {
            FaceCaptureView(
                onCaptured: { template in
                    faceTemplate = template
                    liveness = .done
                    showCamera = false
                },
                onCancel: { showCamera = false })
        }
        .toolbar {
            // O teclado numérico do CPF não tem tecla de retorno; sem isto
            // não há como fechá-lo para alcançar o botão de avançar.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Concluir") { focusedField = nil }
                    .tint(Theme.cyan)
                    .accessibilityIdentifier("fecharTeclado")
            }
        }
    }

    // MARK: Cabeçalho e progresso

    private var header: some View {
        HStack {
            Button(action: retreat) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface1, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")
            Spacer()
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 12)
    }

    private var progressBars: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.cyan : Theme.line)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.bottom, 20)
        .animation(.snappy(duration: 0.25), value: step)
        .accessibilityLabel("Passo \(step.rawValue + 1) de \(Step.allCases.count)")
    }

    // MARK: Passo 1 — identidade

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Vamos começar", "Seus dados ficam protegidos conforme a LGPD.")

            field("Nome completo") {
                TextField("Como está no documento", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .nome)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .cpf }
                    .accessibilityIdentifier("campoNome")
            }
            field("CPF") {
                TextField("000.000.000-00", text: $cpf)
                    .keyboardType(.numberPad)
                    .onChange(of: cpf) { _, new in cpf = CPF.mask(new) }
                    .focused($focusedField, equals: .cpf)
                    .accessibilityIdentifier("campoCPF")
            }
            field("E-mail") {
                TextField("voce@email.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("campoEmail")
            }

            if !cpf.isEmpty, CPF.digits(cpf).count == 11, !CPF.isValid(cpf) {
                Label("CPF inválido", systemImage: "exclamationmark.circle")
                    .font(.auroraCaption).foregroundStyle(Theme.danger)
            }
        }
    }

    // MARK: Passo 2 — prova de vida

    private var livenessStep: some View {
        VStack(spacing: 18) {
            stepTitle("Prova de vida", "Centralize o rosto e mantenha boa iluminação.")

            ZStack {
                Circle()
                    .stroke(liveness == .idle ? Theme.line : Theme.cyan, lineWidth: 2)
                    .frame(width: 196, height: 196)
                if liveness == .scanning {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(liveness == .scanning ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false),
                                   value: liveness)
                }
                Image(systemName: liveness == .done ? "checkmark" : "person.crop.circle")
                    .font(.system(size: liveness == .done ? 46 : 68, weight: .light))
                    .foregroundStyle(liveness == .done ? Theme.cyan : Theme.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            Text(livenessText)
                .font(.auroraBody)
                .foregroundStyle(liveness == .done ? Theme.cyan : Theme.text2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prova de vida. \(livenessText)")
        .accessibilityIdentifier(liveness == .done ? "livenessOK" : "livenessPendente")
    }

    private var livenessText: String {
        switch liveness {
        case .idle: "Toque em Abrir câmera e aproxime o rosto"
        case .scanning: "Analisando…"
        case .done: "Prova de vida confirmada"
        }
    }

    // MARK: Passo 3 — conta e termos

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("Escolha sua conta", "Sem tarifa de manutenção.")

            ForEach(Self.accountOptions, id: \.id) { opt in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { accountKind = opt.id }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(opt.title).font(.display(16, .semibold)).foregroundStyle(Theme.text)
                        Text(opt.subtitle).font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .stroke(accountKind == opt.id ? Theme.cyan : Theme.line,
                                    lineWidth: accountKind == opt.id ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(accountKind == opt.id ? [.isButton, .isSelected] : .isButton)
            }

            Button {
                withAnimation(.snappy(duration: 0.18)) { acceptedTerms.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(acceptedTerms ? Theme.cyan : .clear)
                            .frame(width: 22, height: 22)
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(acceptedTerms ? Theme.cyan : Theme.line, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        if acceptedTerms {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    Text("Li e aceito os termos de uso, contrato de conta e a política de privacidade.")
                        .font(.auroraCaption)
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("Aceitar os termos de uso")
            .accessibilityAddTraits(acceptedTerms ? [.isButton, .isSelected] : .isButton)
        }
    }

    private static let accountOptions = [
        (id: "digital", title: "Conta digital",
         subtitle: "Pix, cartão e rendimento automático de 100% do CDI"),
        (id: "poupanca", title: "Conta poupança",
         subtitle: "Rendimento mensal, ideal para reservas"),
    ]

    // MARK: Passo 4 — criar PIN (novo)

    private var pinStep: some View {
        VStack(spacing: 18) {
            stepTitle(
                pin.count < 4 ? "Crie seu PIN" : "Confirme seu PIN",
                pin.count < 4
                    ? "Quatro dígitos para entrar e autorizar transações."
                    : "Digite os mesmos quatro dígitos de novo."
            )

            PinDots(filled: pin.count < 4 ? pin.count : pinConfirm.count,
                    isError: pinError != nil)
                .padding(.vertical, 12)

            if let pinError {
                Text(pinError).font(.auroraCaption).foregroundStyle(Theme.danger)
            } else {
                Text("Evite sequências como 1234 ou dígitos repetidos.")
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
            }

            Keypad { key in
                switch key {
                case .digit(let d): appendPin(d)
                case .delete:
                    pinError = nil
                    if pin.count < 4 { _ = pin.popLast() } else { _ = pinConfirm.popLast() }
                default: break
                }
            }
            .padding(.top, 4)
        }
    }

    private func appendPin(_ d: String) {
        pinError = nil
        if pin.count < 4 {
            pin += d
            if pin.count == 4, Self.isWeak(pin) {
                pinError = "PIN muito fácil de adivinhar. Escolha outro."
                pin = ""
                Haptics.error()
            }
        } else if pinConfirm.count < 4 {
            pinConfirm += d
            if pinConfirm.count == 4, pinConfirm != pin {
                pinError = "Os PINs não coincidem."
                pinConfirm = ""
                Haptics.error()
            }
        }
    }

    static func isWeak(_ pin: String) -> Bool {
        let digits = pin.compactMap(\.wholeNumberValue)
        guard digits.count == 4 else { return true }
        if Set(digits).count == 1 { return true }                       // 1111
        if zip(digits, digits.dropFirst()).allSatisfy({ $1 == $0 + 1 }) { return true } // 1234
        if zip(digits, digits.dropFirst()).allSatisfy({ $1 == $0 - 1 }) { return true } // 4321
        return false
    }

    // MARK: Navegação

    private var ctaTitle: String {
        switch step {
        case .liveness: liveness == .done ? "Continuar" : "Abrir câmera"
        case _ where submitting: "Enviando…"
        case .account:  "Continuar"
        case .pin:      "Abrir minha conta"
        case .identity: "Continuar"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .identity:
            name.trimmingCharacters(in: .whitespaces).split(separator: " ").count >= 2
                && CPF.isValid(cpf)
                && email.contains("@") && email.contains(".")
        case .liveness: true   // o botão "Capturar" abre a câmera; "Continuar" avança
        case .account:  acceptedTerms
        case .pin:      pin.count == 4 && pinConfirm == pin
        }
    }

    private func advance() {
        guard canAdvance else { return }
        switch step {
        case .identity:
            step = .liveness
        case .liveness:
            if liveness == .done { step = .account }
            else { showCamera = true }        // abre a câmera real
        case .account:
            step = .pin
        case .pin:
            Task { await finish() }
        }
    }

    private func retreat() {
        switch step {
        case .identity: dismiss()
        case .liveness: step = .identity
        case .account:  step = .liveness
        case .pin:
            if !pinConfirm.isEmpty || pin.count == 4 { pin = ""; pinConfirm = ""; pinError = nil }
            else { step = .account }
        }
    }

    private func finish() async {
        let fullName = name.trimmingCharacters(in: .whitespaces).capitalizedWords
        let template = faceTemplate ?? []
        submitting = true; submitError = nil

        // Backend real: cria a conta e cadastra o rosto no servidor.
        if model.usesRemoteBackend {
            do {
                try await model.remoteSignUp(fullName: fullName, cpf: cpf,
                                             email: email, pin: pin, faceFeatures: template)
            } catch {
                submitting = false
                submitError = (error as? APIError)?.message
                    ?? "Não foi possível criar a conta. Tente de novo."
                return
            }
        }

        // PIN local (Face ID / desbloqueio) e identidade lembrada para a
        // tela de bloqueio saber quem é antes do primeiro login.
        do { try model.security.setPIN(pin) }
        catch { submitting = false; pinError = "Não foi possível salvar o PIN."; return }

        model.rememberIdentity(name: fullName, cpf: cpf, email: email)
        submitting = false
        model.phase = .locked
        model.showToast("Conta criada. Entre com seu PIN.")
        dismiss()
    }

    // MARK: Auxiliares de layout

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.auroraTitle).foregroundStyle(Theme.text)
            Text(subtitle).font(.auroraBody).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: step == .identity || step == .account ? .leading : .center)
        .multilineTextAlignment(step == .identity || step == .account ? .leading : .center)
        .accessibilityElement(children: .combine)
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.auroraLabel).foregroundStyle(Theme.text2)
            content()
                .font(.auroraBody)
                .foregroundStyle(Theme.text)
                .padding(16)
                .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.icon)
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
    }
}

// MARK: - CPF

enum CPF {
    static func digits(_ s: String) -> String { s.filter(\.isNumber) }

    static func mask(_ raw: String) -> String {
        let d = String(digits(raw).prefix(11))
        switch d.count {
        case 0...3: return d
        case 4...6: return "\(d.prefix(3)).\(d.dropFirst(3))"
        case 7...9: return "\(d.prefix(3)).\(d.dropFirst(3).prefix(3)).\(d.dropFirst(6))"
        default:
            return "\(d.prefix(3)).\(d.dropFirst(3).prefix(3)).\(d.dropFirst(6).prefix(3))-\(d.dropFirst(9))"
        }
    }

    /// Validação real pelos dígitos verificadores — o protótipo só contava
    /// se havia 11 dígitos.
    static func isValid(_ raw: String) -> Bool {
        let d = digits(raw).compactMap(\.wholeNumberValue)
        guard d.count == 11, Set(d).count > 1 else { return false }
        for check in 0..<2 {
            let slice = d.prefix(9 + check)
            let weightStart = 10 + check
            let sum = slice.enumerated().reduce(0) { $0 + $1.element * (weightStart - $1.offset) }
            let rest = (sum * 10) % 11
            let expected = rest == 10 ? 0 : rest
            if expected != d[9 + check] { return false }
        }
        return true
    }
}

extension String {
    var capitalizedWords: String {
        split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

import SwiftUI

// MARK: - Pix: escolher destinatário

struct PixRecipientStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: FlowSession
    let flow: PixFlow

    @State private var keyText = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { keyText.trimmingCharacters(in: .whitespaces).count >= 5 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Para quem você quer enviar?")
                        .font(.auroraBody).foregroundStyle(Theme.text2)

                    TextField("CPF, e-mail, celular ou chave aleatória", text: $keyText)
                        .font(.auroraBody)
                        .foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .padding(16)
                        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.icon)
                                .stroke(focused ? Theme.cyan : Theme.line, lineWidth: 1)
                        )

                    if !model.contacts.isEmpty {
                        Text("Recentes").font(.auroraLabel).foregroundStyle(Theme.text2)
                        AuroraCard(padding: 12) {
                            VStack(spacing: 0) {
                                ForEach(Array(model.contacts.enumerated()), id: \.element.id) { i, c in
                                    contactRow(c, divider: i < model.contacts.count - 1)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Space.gutter)
            }

            PrimaryButton(title: "Continuar", enabled: isValid) { proceed(with: nil) }
                .padding(Theme.Space.gutter)
        }
    }

    private func contactRow(_ c: Contact, divider: Bool) -> some View {
        Button { proceed(with: c) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text(c.initials)
                        .font(.display(14, .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.cyan, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.auroraBody).foregroundStyle(Theme.text)
                        Text(c.key).font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                }
                .padding(.vertical, 10)
                if divider { Divider().overlay(Theme.line) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enviar Pix para \(c.name)")
    }

    /// Resolve o destinatário e avança. Chave desconhecida vira um contato
    /// novo com nome simulado, como faria a consulta ao Diretório do Pix.
    private func proceed(with contact: Contact?) {
        let resolved: Contact
        if let contact {
            resolved = contact
        } else {
            let key = keyText.trimmingCharacters(in: .whitespaces)
            resolved = model.contacts.first { $0.key == key }
                ?? Contact(name: Self.resolvedName(for: key), key: key)
        }
        session.recipientName = resolved.name
        session.recipientKey = resolved.key
        session.replaceFlow(PixFlow(contact: resolved, scheduledFor: flow.scheduledFor))
        session.advance()
    }

    private static func resolvedName(for key: String) -> String {
        let names = ["Lucas Andrade Reis", "Camila Nogueira", "Diego Martins Alves",
                     "Helena Barros", "Thiago Moreira"]
        return names[abs(key.hashValue) % names.count]
    }
}

// MARK: - Boleto: ler ou digitar o código

struct BoletoScanStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: FlowSession
    let flow: BoletoFlow

    @State private var code = ""
    @FocusState private var focused: Bool

    /// Linha digitável tem 47 dígitos; aceitamos a partir de 20 para o mock.
    private var isValid: Bool { code.filter(\.isNumber).count >= 20 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        code = Self.sampleCode()
                        Haptics.tap()
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.cyan)
                            Text("Ler código de barras")
                                .font(.auroraBody).foregroundStyle(Theme.text)
                            Text("Aponte a câmera para o boleto")
                                .font(.auroraCaption).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .stroke(Theme.cyan.opacity(0.4),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        )
                    }
                    .buttonStyle(.plain)

                    Text("Ou digite a linha digitável")
                        .font(.auroraLabel).foregroundStyle(Theme.text2)

                    TextField("00000.00000 00000.000000 00000.000000 0 00000000000000",
                              text: $code, axis: .vertical)
                        .font(.mono(14))
                        .foregroundStyle(Theme.text)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .lineLimit(2...3)
                        .padding(16)
                        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.icon)
                                .stroke(focused ? Theme.cyan : Theme.line, lineWidth: 1)
                        )
                }
                .padding(Theme.Space.gutter)
            }

            PrimaryButton(title: "Continuar", enabled: isValid) {
                session.replaceFlow(MockData.boleto(for: code))
                session.advance()
            }
            .padding(Theme.Space.gutter)
        }
    }

    private static func sampleCode() -> String {
        (0..<47).map { _ in String(Int.random(in: 0...9)) }.joined()
    }
}

// MARK: - Recarga: número e operadora

struct RecargaPhoneStep: View {
    @Bindable var session: FlowSession
    let flow: RecargaFlow

    @State private var phone = ""
    @FocusState private var focused: Bool

    private var digits: String { phone.filter(\.isNumber) }
    private var isValid: Bool { digits.count == 11 }
    private var carrier: String { isValid ? MockData.carrier(for: digits) : "" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Para qual número?")
                    .font(.auroraBody).foregroundStyle(Theme.text2)

                TextField("(11) 90000-0000", text: $phone)
                    .font(.mono(20))
                    .foregroundStyle(Theme.text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .onChange(of: phone) { _, new in phone = Self.mask(new) }
                    .padding(16)
                    .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.icon)
                            .stroke(focused ? Theme.cyan : Theme.line, lineWidth: 1)
                    )

                if isValid {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.cyan)
                        Text("Operadora identificada: \(carrier)")
                            .font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(Theme.Space.gutter)
            .animation(.snappy(duration: 0.2), value: isValid)

            PrimaryButton(title: "Continuar", enabled: isValid) {
                session.replaceFlow(RecargaFlow(phone: phone, carrier: carrier))
                session.advance()
            }
            .padding(Theme.Space.gutter)
        }
        .onAppear { focused = true }
    }

    static func mask(_ raw: String) -> String {
        let d = String(raw.filter(\.isNumber).prefix(11))
        switch d.count {
        case 0: return ""
        case 1...2: return "(\(d)"
        case 3...7: return "(\(d.prefix(2))) \(d.dropFirst(2))"
        default:
            let body = d.dropFirst(2)
            return "(\(d.prefix(2))) \(body.prefix(5))-\(body.dropFirst(5))"
        }
    }
}

/// Valores pré-definidos de recarga.
struct RecargaPresets: View {
    @Bindable var session: FlowSession
    private let values = [15, 20, 30, 50]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { v in
                Button {
                    session.centsText = String(v * 100)
                    Haptics.tap()
                } label: {
                    Text("R$ \(v)")
                        .font(.auroraLabel)
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.surface1, in: .rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

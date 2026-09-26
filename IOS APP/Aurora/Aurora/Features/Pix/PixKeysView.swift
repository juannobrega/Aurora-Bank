import SwiftUI

struct PixKeysView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddSheet = false
    @State private var pendingDelete: PixKey?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                Text("Você pode ter até 5 chaves. Elas identificam sua conta em um Pix.")
                    .font(.auroraCaption).foregroundStyle(Theme.text2)

                AuroraCard(padding: 12) {
                    if model.pixKeys.isEmpty {
                        EmptyStateView(symbol: "key", title: "Nenhuma chave cadastrada",
                                       message: "Cadastre uma chave para receber Pix.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.pixKeys.enumerated()), id: \.element.id) { i, key in
                                keyRow(key, divider: i < model.pixKeys.count - 1)
                            }
                        }
                    }
                }

                PrimaryButton(title: "Cadastrar chave", enabled: model.pixKeys.count < 5) {
                    showAddSheet = true
                }

                Text("Portabilidade e reivindicação de chave dependem do DICT do Banco Central.")
                    .font(.auroraCaption).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Minhas chaves") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showAddSheet) { AddPixKeySheet() }
        .confirmationDialog(
            "Excluir esta chave?",
            isPresented: .init(get: { pendingDelete != nil },
                               set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                if let k = pendingDelete { model.deletePixKey(k.id) }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Quem já tem essa chave salva não vai conseguir te enviar Pix por ela.")
        }
    }

    private func keyRow(_ key: PixKey, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "key.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface2, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.kind.title).font(.auroraBody).foregroundStyle(Theme.text)
                    Text(key.masked)
                        .font(.mono(12)).foregroundStyle(Theme.text2)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = key.value
                    model.showToast("Chave copiada")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14)).foregroundStyle(Theme.text2)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copiar chave \(key.kind.title)")

                Button { pendingDelete = key } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14)).foregroundStyle(Theme.danger)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Excluir chave \(key.kind.title)")
            }
            .padding(.vertical, 10)
            if divider { Divider().overlay(Theme.line) }
        }
    }
}

/// Cadastro de chave: o protótipo só criava aleatórias.
struct AddPixKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PixKey.Kind = .aleatoria

    private var available: [PixKey.Kind] {
        PixKey.Kind.allCases.filter { k in
            k == .aleatoria || !model.pixKeys.contains { $0.kind == k }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Que tipo de chave?").font(.auroraBody).foregroundStyle(Theme.text2)

                ForEach(available, id: \.self) { k in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { kind = k }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(k.title).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                                Text(subtitle(for: k)).font(.auroraCaption).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            if kind == k {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.cyan)
                            }
                        }
                        .padding(16)
                        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.icon)
                                .stroke(kind == k ? Theme.cyan : Theme.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                PrimaryButton(title: "Cadastrar") { register() }
            }
            .padding(Theme.Space.gutter)
            .navigationTitle("Nova chave")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.tint(Theme.text2)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { kind = available.first ?? .aleatoria }
    }

    private func subtitle(for k: PixKey.Kind) -> String {
        switch k {
        case .cpf: "Seu CPF cadastrado na conta"
        case .celular: "Confirmado por SMS"
        case .email: "Confirmado por link"
        case .aleatoria: "Chave gerada pelo banco, sem expor seus dados"
        }
    }

    private func register() {
        switch kind {
        case .aleatoria:
            model.addRandomPixKey()
        case .cpf:
            model.pixKeys.append(PixKey(kind: .cpf, value: model.user.cpf,
                                        masked: Self.maskCPF(model.user.cpf)))
            model.showToast("Chave CPF cadastrada")
        case .celular:
            model.pixKeys.append(PixKey(kind: .celular, value: model.user.phone,
                                        masked: Self.maskPhone(model.user.phone)))
            model.showToast("Enviamos um código por SMS")
        case .email:
            model.pixKeys.append(PixKey(kind: .email, value: model.user.email,
                                        masked: Self.maskEmail(model.user.email)))
            model.showToast("Confirme pelo link enviado ao seu e-mail")
        }
        dismiss()
    }

    static func maskCPF(_ s: String) -> String {
        let d = s.filter(\.isNumber)
        guard d.count == 11 else { return s }
        return "***.\(d.dropFirst(3).prefix(3)).\(d.dropFirst(6).prefix(3))-**"
    }
    static func maskPhone(_ s: String) -> String {
        let d = s.filter(\.isNumber)
        guard d.count >= 10 else { return s }
        return "(\(d.prefix(2))) 9****-\(d.suffix(4))"
    }
    static func maskEmail(_ s: String) -> String {
        let parts = s.split(separator: "@")
        guard parts.count == 2, let local = parts.first else { return s }
        return "\(local.prefix(2))***@\(parts[1])"
    }
}

/// Limites do Pix — no protótipo, "Limites" só redirecionava para o Perfil.
struct PixLimitsView: View {
    @Environment(AppModel.self) private var model
    @State private var dayLimit: Double = 5_000
    @State private var nightLimitValue: Double = 1_000

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Limite diurno").font(.auroraLabel).foregroundStyle(Theme.text2)
                        Text(Money(Decimal(dayLimit)).formatted)
                            .font(.mono(24, .semibold)).foregroundStyle(Theme.text)
                        Slider(value: $dayLimit, in: 500...20_000, step: 500)
                            .tint(Theme.cyan)
                        Text("Entre 6h e 20h").font(.auroraCaption).foregroundStyle(Theme.text3)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $model.settings.nightLimitEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Limite noturno").font(.auroraBody).foregroundStyle(Theme.text)
                                Text("Entre 20h e 6h").font(.auroraCaption).foregroundStyle(Theme.text2)
                            }
                        }
                        .tint(Theme.cyan)

                        if model.settings.nightLimitEnabled {
                            Text(Money(Decimal(nightLimitValue)).formatted)
                                .font(.mono(24, .semibold)).foregroundStyle(Theme.text)
                            Slider(value: $nightLimitValue, in: 200...5_000, step: 100)
                                .tint(Theme.cyan)
                                .onChange(of: nightLimitValue) { _, new in
                                    model.settings.nightLimit = Money(Decimal(new))
                                }
                        }
                    }
                }

                Text("Aumentos de limite passam por análise e valem a partir do dia seguinte, conforme a regulação do Banco Central.")
                    .font(.auroraCaption).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Limites do Pix") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .onAppear {
            nightLimitValue = NSDecimalNumber(decimal: model.settings.nightLimit.amount).doubleValue
        }
    }
}

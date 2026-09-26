import SwiftUI

/// Central de segurança. No protótipo, todas as quatro linhas eram toast.
/// Aqui "Alterar PIN" muda o PIN de verdade no Keychain.
struct SecurityView: View {
    @Environment(AppModel.self) private var model
    @State private var showChangePin = false
    @State private var confirmRevoke = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                AuroraCard(padding: 12) {
                    VStack(spacing: 0) {
                        ActionRow(symbol: "lock.rotation", title: "Alterar PIN",
                                  subtitle: "Quatro dígitos de acesso") {
                            showChangePin = true
                        }
                        ActionRow(symbol: "iphone", title: "Dispositivos confiáveis",
                                  subtitle: "iPhone · este aparelho") {
                            model.showToast("1 dispositivo autorizado")
                        }
                        ActionRow(symbol: "xmark.shield", title: "Encerrar outras sessões",
                                  subtitle: "Desconecta todos os outros aparelhos") {
                            confirmRevoke = true
                        }
                        ActionRow(symbol: "hand.raised.fill", title: "Privacidade e dados (LGPD)",
                                  subtitle: "Consentimentos e Open Finance",
                                  showsDivider: false) {
                            model.showToast("Você tem 2 consentimentos ativos")
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Dicas de segurança", systemImage: "info.circle")
                            .font(.auroraLabel).foregroundStyle(Theme.text2)
                        tip("O Aurora nunca pede seu PIN por telefone, SMS ou e-mail.")
                        tip("Desconfie de links que pedem para você reinstalar o app.")
                        tip("Ative a biometria para não digitar o PIN em público.")
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Segurança") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showChangePin) { ChangePinSheet() }
        .confirmationDialog("Encerrar outras sessões?", isPresented: $confirmRevoke,
                            titleVisibility: .visible) {
            Button("Encerrar", role: .destructive) {
                model.showToast("Outras sessões encerradas")
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.cyan).frame(width: 5, height: 5).padding(.top, 6)
            Text(text).font(.auroraCaption).foregroundStyle(Theme.text2)
        }
    }
}

struct ChangePinSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Stage { case verify, create, confirm }
    @State private var stage: Stage = .verify
    @State private var entry = ""
    @State private var newPin = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text(title).font(.auroraHeadline).foregroundStyle(Theme.text)
                    Text(error ?? subtitle)
                        .font(.auroraBody)
                        .foregroundStyle(error != nil ? Theme.danger : Theme.text2)
                        .multilineTextAlignment(.center)
                    PinDots(filled: entry.count, isError: error != nil).padding(.top, 8)
                }
                .frame(maxHeight: .infinity)

                Keypad { key in
                    switch key {
                    case .digit(let d): append(d)
                    case .delete: error = nil; _ = entry.popLast()
                    default: break
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.gutter)
            }
            .navigationTitle("Alterar PIN")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.tint(Theme.text2)
                }
            }
        }
    }

    private var title: String {
        switch stage {
        case .verify: "PIN atual"
        case .create: "Novo PIN"
        case .confirm: "Confirme o novo PIN"
        }
    }

    private var subtitle: String {
        switch stage {
        case .verify: "Confirme que é você"
        case .create: "Escolha quatro dígitos"
        case .confirm: "Digite os mesmos quatro dígitos"
        }
    }

    private func append(_ d: String) {
        guard entry.count < 4 else { return }
        error = nil
        entry += d
        guard entry.count == 4 else { return }

        switch stage {
        case .verify:
            if model.security.verifyPIN(entry) {
                entry = ""; stage = .create
            } else {
                fail("PIN incorreto.")
            }
        case .create:
            if OnboardingView.isWeak(entry) {
                fail("PIN muito fácil de adivinhar.")
            } else {
                newPin = entry; entry = ""; stage = .confirm
            }
        case .confirm:
            if entry == newPin {
                do {
                    try model.security.setPIN(newPin)
                    Haptics.success()
                    model.showToast("PIN alterado")
                    dismiss()
                } catch {
                    fail("Não foi possível salvar o novo PIN.")
                }
            } else {
                fail("Os PINs não coincidem.")
            }
        }
    }

    private func fail(_ message: String) {
        Haptics.error()
        error = message
        entry = ""
    }
}

/// Central de mensagens — inexistente no protótipo, que só tinha um toast.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                if model.notifications.isEmpty {
                    EmptyStateView(symbol: "bell.slash", title: "Nenhuma mensagem")
                } else {
                    AuroraCard(padding: 12) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.notifications.enumerated()), id: \.element.id) { i, n in
                                notificationRow(n, divider: i < model.notifications.count - 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            ScreenHeader("Notificações") {
                if model.unreadNotifications > 0 {
                    Button("Marcar lidas") { model.markAllNotificationsRead() }
                        .font(.auroraLabel)
                        .tint(Theme.cyan)
                }
            }
        }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .onDisappear { model.markAllNotificationsRead() }
    }

    private func notificationRow(_ n: AppNotification, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: n.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(n.isRead ? Theme.text2 : Theme.cyan)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface2, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(n.title)
                            .font(.display(15, n.isRead ? .regular : .semibold))
                            .foregroundStyle(Theme.text)
                        if !n.isRead {
                            Circle().fill(Theme.cyan).frame(width: 6, height: 6)
                        }
                    }
                    Text(n.message).font(.auroraCaption).foregroundStyle(Theme.text2)
                    Text(Self.relative(n.date)).font(.auroraCaption).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            if divider { Divider().overlay(Theme.line) }
        }
        .accessibilityElement(children: .combine)
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: .now)
    }
}

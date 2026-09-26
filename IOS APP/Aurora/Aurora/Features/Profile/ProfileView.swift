import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                identityCard

                AuroraCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Acesso e preferências")
                            .font(.auroraLabel).foregroundStyle(Theme.text2)
                            .padding(.bottom, 6)
                        toggleRow("Entrar com \(model.security.biometryType.title)",
                                  "Biometria no lugar do PIN",
                                  $model.settings.biometricsEnabled)
                        Divider().overlay(Theme.line)
                        toggleRow("Ocultar saldo ao abrir",
                                  "Valores escondidos na tela inicial",
                                  $model.settings.hideBalanceOnOpen)
                        Divider().overlay(Theme.line)
                        toggleRow("Notificações de transação",
                                  "Aviso a cada compra ou Pix",
                                  $model.settings.transactionAlerts)
                        Divider().overlay(Theme.line)
                        toggleRow("Limite noturno do Pix",
                                  "Até \(model.settings.nightLimit.formatted) entre 20h e 6h",
                                  $model.settings.nightLimitEnabled)
                    }
                }

                AuroraCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Segurança")
                            .font(.auroraLabel).foregroundStyle(Theme.text2)
                            .padding(.bottom, 4)
                        NavigationLink(value: Route.security) {
                            ActionRowLabel(symbol: "shield.fill",
                                           title: "Central de segurança",
                                           subtitle: "PIN, dispositivos e sessões")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Route.notifications) {
                            ActionRowLabel(symbol: "bell.fill",
                                           title: "Notificações",
                                           subtitle: model.unreadNotifications > 0
                                               ? "\(model.unreadNotifications) não lidas"
                                               : "Tudo em dia")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Route.support) {
                            ActionRowLabel(symbol: "bubble.left.and.text.bubble.right.fill",
                                           title: "Ajuda e atendimento",
                                           subtitle: "Chat, FAQ e chamados",
                                           showsDivider: false)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button { confirmSignOut = true } label: {
                    Text("Sair da conta")
                        .font(.auroraBody).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon)
                            .stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Text("Aurora Bank · versão 1.0 (mock)")
                    .font(.auroraCaption).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Perfil").font(.auroraTitle).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 10)
            .background(Theme.navy)
        }
        .auroraBackground()
        .auroraRoutes()
        .navigationBarHidden(true)
        .confirmationDialog("Sair da conta?", isPresented: $confirmSignOut,
                            titleVisibility: .visible) {
            Button("Sair", role: .destructive) { model.signOut() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Você vai precisar cadastrar o PIN de novo ao entrar.")
        }
    }

    private var identityCard: some View {
        AuroraCard {
            HStack(spacing: 14) {
                Text(model.user.initials)
                    .font(.display(18, .semibold)).foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Theme.cyan, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.user.name).font(.auroraHeadline).foregroundStyle(Theme.text)
                    Text("Ag \(model.user.agency) · Conta \(model.user.account)")
                        .font(.auroraCaption).foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleRow(_ title: String, _ subtitle: String,
                           _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.auroraBody).foregroundStyle(Theme.text)
                Text(subtitle).font(.auroraCaption).foregroundStyle(Theme.text2)
            }
        }
        .tint(Theme.cyan)
        .padding(.vertical, 9)
    }
}

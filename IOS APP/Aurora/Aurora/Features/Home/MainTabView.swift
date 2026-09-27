import SwiftUI

/// Destinos empilhados, navegados por `NavigationStack` em cada aba.
enum Route: Hashable {
    case statement
    case transaction(UUID)
    case pixReceive
    case pixKeys
    case pixLimits
    case credit
    case invest
    case holding(String)
    case plan(PlanTab)
    case goalDetail(UUID)
    case payments
    case notifications
    case support
    case security
    case loanDetail(UUID)
    case cardSettings
}

enum PlanTab: Hashable { case goals, spending }

/// Permite que uma tela peça a troca de aba — atalhos que apontam para uma
/// aba devem selecioná-la, não empurrar uma cópia na pilha atual (a cópia
/// não teria botão Voltar e prenderia o usuário).
@Observable
@MainActor
final class TabRouter {
    var selection: MainTabView.Section = .home
    func select(_ s: MainTabView.Section) { selection = s }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var router = TabRouter()

    /// Não pode se chamar `Tab`: colide com o `Tab` do SwiftUI.
    enum Section: Hashable, CaseIterable {
        case home, statement, pix, cards, profile

        var label: String {
            switch self {
            case .home: "Início"
            case .statement: "Extrato"
            case .pix: "Pix"
            case .cards: "Cartões"
            case .profile: "Perfil"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .statement: "list.bullet.rectangle.fill"
            case .pix: "arrow.left.arrow.right"
            case .cards: "creditcard.fill"
            case .profile: "person.fill"
            }
        }
    }

    var body: some View {
        Group {
            switch router.selection {
            case .home:      NavigationStack { HomeView() }
            case .statement: NavigationStack { StatementView() }
            case .pix:       NavigationStack { PixView() }
            case .cards:     NavigationStack { CardsView() }
            case .profile:   NavigationStack { ProfileView() }
            }
        }
        .environment(router)
        // safeAreaInset reserva o espaço da barra E respeita a home
        // indicator sozinho — o conteúdo nunca fica escondido atrás dela, e
        // a barra não colide com a barra do sistema.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AuroraTabBar(selection: Bindable(router).selection)
                .padding(.horizontal, Theme.Space.base)
                .padding(.top, Theme.Space.sm)
                // Folga mínima abaixo da barra em aparelhos de borda reta;
                // onde há home indicator, o safeAreaInset já a afasta.
                .padding(.bottom, Theme.Space.xs)
                .background(
                    // Um leve degradê para o conteúdo não "grudar" na barra
                    // ao rolar por baixo dela.
                    LinearGradient(colors: [Theme.navy.opacity(0), Theme.navy],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                        .allowsHitTesting(false),
                    alignment: .bottom
                )
        }
    }
}

/// Barra flutuante: a aba ativa expande e revela o rótulo sobre o gradiente
/// da marca — o padrão definido no design system.
struct AuroraTabBar: View {
    @Binding var selection: MainTabView.Section

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTabView.Section.allCases, id: \.self) { section in
                let active = selection == section
                Button {
                    withAnimation(Theme.Motion.snap) { selection = section }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 17))
                        if active {
                            Text(section.label)
                                .font(.display(14, .medium))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(active ? .white : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        if active {
                            Capsule().fill(Theme.actionGradient)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: active ? .infinity : 56)
                .accessibilityLabel(section.label)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .background {
            Capsule()
                .fill(Theme.surface1)
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        }
    }
}

/// Resolve um `Route` na view correspondente. Usado por todas as abas.
struct RouteDestination: View {
    @Environment(AppModel.self) private var model
    let route: Route

    var body: some View {
        switch route {
        case .statement:
            StatementView()
        case .transaction(let id):
            if let tx = model.ledger.transaction(id: id) {
                TransactionDetailView(transaction: tx)
            } else {
                EmptyStateView(symbol: "doc.questionmark", title: "Transação não encontrada")
            }
        case .pixReceive:    PixReceiveView()
        case .pixKeys:       PixKeysView()
        case .pixLimits:     PixLimitsView()
        case .credit:        CreditView()
        case .invest:        InvestView()
        case .holding(let id):
            if let h = model.holdings.first(where: { $0.id == id }) {
                HoldingDetailView(holding: h)
            } else {
                EmptyStateView(symbol: "chart.bar", title: "Posição encerrada")
            }
        case .plan(let tab):  PlanView(initialTab: tab)
        case .goalDetail(let id):
            if let g = model.goals.first(where: { $0.id == id }) {
                GoalDetailView(goal: g)
            } else {
                EmptyStateView(symbol: "banknote", title: "Cofrinho removido")
            }
        case .payments:      PaymentsView()
        case .notifications: NotificationsView()
        case .support:       SupportView()
        case .security:      SecurityView()
        case .loanDetail(let id):
            if let loan = model.loans.first(where: { $0.id == id }) {
                LoanDetailView(loan: loan)
            } else {
                EmptyStateView(symbol: "doc.text", title: "Contrato não encontrado")
            }
        case .cardSettings:  CardSettingsView()
        }
    }
}

/// Aplica o `navigationDestination` padrão do app numa pilha.
extension View {
    func auroraRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}

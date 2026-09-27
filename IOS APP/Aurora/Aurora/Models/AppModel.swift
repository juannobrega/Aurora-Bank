import Foundation
import SwiftUI
import LocalAuthentication

/// Preferências do usuário (os toggles do Perfil).
struct Settings: Codable, Sendable, Hashable {
    var biometricsEnabled = true
    var hideBalanceOnOpen = false
    var transactionAlerts = true
    var nightLimitEnabled = true
    var nightLimit: Money = 1_000
}

/// Notificação na central de mensagens — o protótipo só tinha um toast.
struct AppNotification: Identifiable, Sendable, Hashable {
    enum Kind: Sendable { case transaction, security, offer, bill }
    var id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var date: Date = .now
    var isRead = false

    var symbol: String {
        switch kind {
        case .transaction: "arrow.left.arrow.right"
        case .security: "shield.fill"
        case .offer: "sparkles"
        case .bill: "calendar.badge.exclamationmark"
        }
    }
}

enum AppPhase: Sendable, Equatable {
    case welcome, onboarding, locked, ready
}

/// Estado central do app. Tudo que é financeiro deriva do `ledger`.
@Observable
@MainActor
final class AppModel {
    // Serviços
    private let account: any AccountServicing
    let security: any SecurityServicing

    // Estado
    var phase: AppPhase = .welcome
    var isLoading = false
    var loadError: String?

    var user = User(name: "", cpf: "", email: "", phone: "")
    var ledger = Ledger(openingBalance: 0)
    var card = Card(invoiceDue: .now)
    var holdings: [Holding] = []
    var goals: [Goal] = []
    var loans: [Loan] = []
    var pixKeys: [PixKey] = []
    var contacts: [Contact] = []
    var monthlyBudget: Money = 4_000
    var creditScore = 742
    var notifications: [AppNotification] = []

    var settings = Settings()
    var hideBalance = false
    var toast: String?

    private var toastTask: Task<Void, Never>?

    /// Cliente da API real, quando não está em modo mock. O login e os
    /// fluxos usam este para falar com bank.pulsaz.com.br.
    let api: AuroraAPIClient? = Backend.useMock ? nil : Backend.api

    init(account: any AccountServicing = Backend.accountService(),
         security: any SecurityServicing = KeychainSecurityService()) {
        self.account = account
        self.security = security
        // Testes de UI precisam de um app sempre no estado inicial: o PIN
        // fica no Keychain e sobrevive entre execuções.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-auroraResetState") { security.clearPIN() }

        // Entra direto na home, pulando onboarding e PIN. Só para testes de
        // navegação — o fluxo de entrada tem os seus próprios testes.
        if args.contains("-auroraAutoLogin") {
            self.phase = .ready
        } else {
            self.phase = security.hasPIN() ? .locked : .welcome
        }
        loadRememberedIdentity()
    }

    // MARK: - Ciclo de vida

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            let snap = try await account.loadAccount()
            user = snap.user
            ledger = snap.ledger
            card = snap.card
            holdings = snap.holdings
            goals = snap.goals
            loans = snap.loans
            pixKeys = snap.pixKeys
            contacts = snap.contacts
            monthlyBudget = snap.monthlyBudget
            creditScore = snap.creditScore
            notifications = Self.seedNotifications()
            hideBalance = settings.hideBalanceOnOpen
        } catch {
            loadError = "Não foi possível carregar sua conta. Tente novamente."
        }
        isLoading = false
    }

    func unlock() {
        hideBalance = settings.hideBalanceOnOpen
        phase = .ready
    }

    // MARK: - Autenticação na API (quando não é mock)

    /// Cria a conta no servidor: dados + rosto. Devolve o id do usuário.
    /// A prova de vida e o template são gerados no app (ver nota de segurança
    /// no backend: hoje o servidor confia no cliente).
    func remoteSignUp(fullName: String, cpf: String, email: String,
                      pin: String, faceFeatures: [Float]) async throws {
        guard let api else { return }
        let userId = try await api.signUp(.init(
            fullName: fullName, cpf: cpf, email: email, pin: pin, phone: nil))
        try await api.enrollFace(.init(
            userId: userId, features: faceFeatures, algorithm: "aurora-face-v1",
            quality: 0.9, livenessPassed: true))
    }

    /// Entra por PIN contra a API e carrega a conta.
    func remoteLoginPin(cpf: String, pin: String) async throws {
        guard let api else { return }
        try await api.loginWithPin(cpf: cpf, pin: pin)
        await load()
    }

    /// Entra por rosto contra a API.
    func remoteLoginFace(cpf: String, features: [Float]) async throws {
        guard let api else { return }
        try await api.loginWithFace(cpf: cpf, features: features,
                                    algorithm: "aurora-face-v1", livenessPassed: true)
        await load()
    }

    var usesRemoteBackend: Bool { api != nil }

    /// Lembra quem é o dono deste aparelho entre sessões, para a tela de
    /// bloqueio saudar pelo nome antes de carregar o snapshot. Só dados de
    /// identificação — nunca senha ou saldo.
    func rememberIdentity(name: String, cpf: String, email: String) {
        let d = UserDefaults.standard
        d.set(name, forKey: "aurora.user.name")
        d.set(cpf, forKey: "aurora.user.cpf")
        d.set(email, forKey: "aurora.user.email")
        user = User(name: name, cpf: cpf, email: email, phone: "")
    }

    /// CPF lembrado, para o login por PIN não pedir o CPF de novo.
    var rememberedCpf: String? {
        UserDefaults.standard.string(forKey: "aurora.user.cpf")
    }

    private func loadRememberedIdentity() {
        let d = UserDefaults.standard
        if let name = d.string(forKey: "aurora.user.name") {
            user = User(name: name,
                        cpf: d.string(forKey: "aurora.user.cpf") ?? "",
                        email: d.string(forKey: "aurora.user.email") ?? "", phone: "")
        }
    }

    func lock() { phase = .locked }

    func signOut() {
        security.clearPIN()
        let d = UserDefaults.standard
        ["aurora.user.name", "aurora.user.cpf", "aurora.user.email"].forEach(d.removeObject(forKey:))
        if let api { Task { await api.logout() } }
        phase = .welcome
        ledger = Ledger(openingBalance: 0)
        holdings = []; goals = []; loans = []; notifications = []
    }

    // MARK: - Derivados

    var balance: Money { ledger.balance }
    var investedTotal: Money { holdings.reduce(Money.zero) { $0 + $1.current } }
    var investedEarnings: Money { holdings.reduce(Money.zero) { $0 + $1.earnings } }
    var savedTotal: Money { goals.reduce(Money.zero) { $0 + $1.saved } }
    var invoice: Money { ledger.creditInvoice }
    var availableCardLimit: Money { max(.zero, card.limit - invoice) }
    var unreadNotifications: Int { notifications.filter { !$0.isRead }.count }
    var activeLoan: Loan? { loans.first { !$0.isSettled } }

    var monthSpending: Money { ledger.totalSpending(in: .currentMonth) }
    var budgetRemaining: Money { max(.zero, monthlyBudget - monthSpending) }
    var budgetProgress: Double {
        guard monthlyBudget.amount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: monthSpending.amount / monthlyBudget.amount).doubleValue)
    }

    var flowContext: FlowContext {
        FlowContext(
            balance: balance,
            nightLimitEnabled: settings.nightLimitEnabled,
            nightLimit: settings.nightLimit,
            isNightTime: FlowContext.isNight()
        )
    }

    // MARK: - Mutações de domínio

    func invest(_ amount: Money, in product: InvestmentProduct) {
        if let i = holdings.firstIndex(where: { $0.id == product.id }) {
            holdings[i].invested += amount
            holdings[i].current += amount
        } else {
            holdings.append(Holding(id: product.id, invested: amount, current: amount))
        }
    }

    func redeem(_ amount: Money, from holdingID: String) {
        guard let i = holdings.firstIndex(where: { $0.id == holdingID }) else { return }
        holdings[i].current = max(.zero, holdings[i].current - amount)
        // Reduz o aportado proporcionalmente para manter a rentabilidade coerente.
        holdings[i].invested = min(holdings[i].invested, holdings[i].current)
        if holdings[i].current.isZero { holdings.remove(at: i) }
    }

    func deposit(_ amount: Money, to goalID: UUID) {
        guard let i = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[i].saved += amount
    }

    func withdraw(_ amount: Money, from goalID: UUID) {
        guard let i = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[i].saved = max(.zero, goals[i].saved - amount)
    }

    func addGoal(_ goal: Goal) { goals.append(goal) }

    func deleteGoal(_ id: UUID) {
        guard let g = goals.first(where: { $0.id == id }) else { return }
        if !g.saved.isZero {
            ledger.record(Transaction(
                title: "Resgate do cofrinho",
                counterparty: g.name,
                amount: g.saved,
                category: .investimento,
                method: .cofrinho
            ))
        }
        goals.removeAll { $0.id == id }
    }

    @discardableResult
    func contractLoan(principal: Money, months: Int, monthlyRate: Decimal) -> Loan {
        let pmt = Loan.payment(principal: principal, monthlyRate: monthlyRate, months: months)
        let cal = Calendar.current
        let schedule = (1...months).map { n in
            Installment(
                number: n, total: months, amount: pmt,
                dueDate: cal.date(byAdding: .month, value: n, to: .now) ?? .now
            )
        }
        let loan = Loan(principal: principal, monthlyRate: monthlyRate,
                        installments: schedule, contractedAt: .now)
        loans.append(loan)
        return loan
    }

    /// Paga a próxima parcela em aberto. Devolve `false` se faltar saldo.
    @discardableResult
    func payNextInstallment(of loanID: UUID) -> Bool {
        guard let li = loans.firstIndex(where: { $0.id == loanID }),
              let next = loans[li].nextDue,
              let ii = loans[li].installments.firstIndex(where: { $0.id == next.id })
        else { return false }
        guard next.amount <= balance else {
            showToast("Saldo insuficiente para pagar a parcela")
            return false
        }
        loans[li].installments[ii].paidAt = .now
        ledger.record(Transaction(
            title: "Parcela de empréstimo",
            counterparty: next.label,
            amount: -next.amount,
            category: .credito,
            method: .emprestimo
        ))
        showToast("Parcela \(next.number) paga")
        return true
    }

    /// Paga a fatura do cartão com o saldo.
    @discardableResult
    func payInvoice() -> Bool {
        let due = invoice
        guard due > .zero else { showToast("Nenhuma fatura em aberto"); return false }
        guard due <= balance else { showToast("Saldo insuficiente"); return false }
        ledger.record(Transaction(
            title: Ledger.invoicePaymentTitle,
            counterparty: "Cartão Aurora",
            amount: -due,
            category: .credito,
            method: .credito
        ))
        showToast("Fatura paga")
        return true
    }

    /// Parcela a fatura: quita a fatura atual e abre um empréstimo equivalente.
    func installInvoice(months: Int) {
        let due = invoice
        guard due > .zero else { showToast("Nenhuma fatura para parcelar"); return }
        ledger.record(Transaction(
            title: Ledger.invoicePaymentTitle,
            counterparty: "Parcelamento em \(months)x",
            amount: -due,
            category: .credito,
            method: .credito
        ))
        ledger.record(Transaction(
            title: "Crédito de parcelamento",
            counterparty: "Fatura parcelada",
            amount: due,
            category: .credito,
            method: .emprestimo
        ))
        contractLoan(principal: due, months: months, monthlyRate: 0.0199)
        showToast("Fatura parcelada em \(months)x")
    }

    func rememberContact(_ contact: Contact) {
        guard !contacts.contains(where: { $0.key == contact.key }) else {
            // Move para o início (mais recente).
            contacts.removeAll { $0.key == contact.key }
            contacts.insert(contact, at: 0)
            return
        }
        contacts.insert(contact, at: 0)
    }

    func addRandomPixKey() {
        let uuid = UUID().uuidString.lowercased()
        pixKeys.append(PixKey(kind: .aleatoria, value: uuid, masked: uuid))
        showToast("Chave aleatória cadastrada")
    }

    func deletePixKey(_ id: UUID) {
        pixKeys.removeAll { $0.id == id }
        showToast("Chave excluída")
    }

    func markAllNotificationsRead() {
        for i in notifications.indices { notifications[i].isRead = true }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.snappy(duration: 0.25)) { self?.toast = nil }
            }
        }
    }

    // MARK: - Seed

    private static func seedNotifications() -> [AppNotification] {
        [
            AppNotification(kind: .transaction, title: "Pix recebido",
                            message: "R$ 150,00 de João Pedro Lima",
                            date: .now.addingTimeInterval(-3_600)),
            AppNotification(kind: .bill, title: "Fatura fecha em 4 dias",
                            message: "Programe o pagamento para não pagar juros.",
                            date: .now.addingTimeInterval(-28_000)),
            AppNotification(kind: .security, title: "Novo acesso reconhecido",
                            message: "iPhone 15 · São Paulo, SP",
                            date: .now.addingTimeInterval(-90_000), isRead: true),
            AppNotification(kind: .offer, title: "Seu limite pode aumentar",
                            message: "Score 742 libera análise de novo limite.",
                            date: .now.addingTimeInterval(-180_000), isRead: true),
        ]
    }
}

import Foundation

/// Converte os DTOs da API para os tipos de domínio que as views já usam.
/// Manter o mapeamento num só lugar deixa as telas alheias à forma do JSON.
enum DTOMapper {

    static func category(_ raw: String) -> Category {
        Category(rawValue: raw) ?? .outros
    }
    static func method(_ raw: String) -> PaymentMethod {
        PaymentMethod(rawValue: raw) ?? .pix
    }

    static func transaction(_ d: DTO.Transaction) -> Transaction {
        Transaction(
            id: UUID(uuidString: d.id) ?? UUID(),
            date: d.occurredAt,
            title: d.title,
            counterparty: d.counterparty,
            amount: d.isCredit ? Money(cents: d.amountCents)
                               : -Money(cents: d.amountCents).magnitude,
            category: category(d.category),
            method: method(d.method),
            authCode: d.authCode
        )
    }

    static func goal(_ d: DTO.Goal) -> Goal {
        Goal(
            id: UUID(uuidString: d.id) ?? UUID(),
            name: d.name,
            saved: Money(cents: d.savedCents),
            target: Money(cents: d.targetCents),
            symbol: d.symbol,
            deadline: d.deadline.flatMap(Self.date)
        )
    }

    static func holding(_ d: DTO.Holding) -> Holding {
        Holding(id: d.productId, invested: d.invested.money, current: d.current.money)
    }

    static func card(_ d: DTO.Card) -> Card {
        Card(
            kind: d.kind == "virtual" ? .virtual : .fisico,
            isBlocked: d.blocked,
            limit: d.creditLimit.money,
            invoiceDue: date(d.expiry) ?? .now.addingTimeInterval(86_400 * 15),
            number: "5412 7830 1195 2267",
            cvv: "318",
            expiry: d.expiry
        )
    }

    static func loan(_ d: DTO.Loan) -> Loan {
        Loan(
            id: UUID(uuidString: d.id) ?? UUID(),
            principal: Money(cents: d.principalCents),
            monthlyRate: 0.0249,
            installments: d.schedule.map { i in
                Installment(
                    id: UUID(uuidString: i.id) ?? UUID(),
                    number: i.number, total: d.installments,
                    amount: Money(cents: i.amountCents),
                    dueDate: date(i.dueDate) ?? .now,
                    paidAt: i.paid ? .now : nil
                )
            },
            contractedAt: .now
        )
    }

    static func pixKey(_ d: DTO.PixKey) -> PixKey {
        let kind = PixKey.Kind(rawValue: d.kind) ?? .aleatoria
        return PixKey(kind: kind, value: d.value, masked: mask(d.value, kind: kind))
    }

    static func contact(_ d: DTO.Contact) -> Contact {
        Contact(name: d.name, key: d.keyValue, bank: d.bank ?? "Banco Aurora")
    }

    /// Monta o `AccountSnapshot` completo a partir do snapshot da API mais as
    /// listas que o app carrega em paralelo (chaves, contatos, empréstimos).
    static func accountSnapshot(_ s: DTO.Snapshot, pixKeys: [DTO.PixKey],
                                contacts: [DTO.Contact], loans: [DTO.Loan]) -> AccountSnapshot {
        // O saldo vem pronto da API; o ledger local nasce dele mais as
        // transações recentes, para as telas que agrupam por dia.
        let txs = s.recentTransactions.map(transaction)
        let opening = Money(cents: s.balanceCents)
            - txs.reduce(Money.zero) { $0 + $1.amount }

        return AccountSnapshot(
            user: User(name: s.user.fullName, cpf: s.user.maskedCpf,
                       email: s.user.email, phone: ""),
            ledger: Ledger(openingBalance: opening, transactions: txs),
            card: card(s.card),
            holdings: s.holdings.map(holding),
            goals: s.goals.map(goal),
            loans: loans.map(loan),
            pixKeys: pixKeys.map(pixKey),
            contacts: contacts.map(contact),
            monthlyBudget: Money(cents: s.monthlyBudgetCents),
            creditScore: s.creditScore
        )
    }

    // MARK: Auxiliares

    private static func date(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        return f.date(from: raw)
    }

    private static func mask(_ value: String, kind: PixKey.Kind) -> String {
        switch kind {
        case .cpf where value.count >= 11:
            let d = value.filter(\.isNumber)
            return d.count == 11 ? "***.\(d.dropFirst(3).prefix(3)).\(d.dropFirst(6).prefix(3))-**" : value
        case .email:
            return value
        default:
            return value.count > 12 ? "\(value.prefix(8))…" : value
        }
    }
}

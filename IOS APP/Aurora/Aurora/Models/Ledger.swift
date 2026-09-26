import Foundation

/// Agrupamento de transações por dia, para o extrato.
struct TransactionGroup: Identifiable, Hashable {
    var id: Date { day }
    let day: Date
    var items: [Transaction]

    var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Hoje" }
        if cal.isDateInYesterday(day) { return "Ontem" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = cal.isDate(day, equalTo: .now, toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return f.string(from: day)
    }
}

/// Fatia de gasto por categoria, derivada do ledger.
struct CategorySpend: Identifiable, Hashable {
    var id: Category { category }
    let category: Category
    let total: Money
    /// Fração do maior gasto do período — usado para a largura da barra.
    var ratio: Double
}

/// Livro-razão: a **única** fonte de verdade financeira.
///
/// Saldo, extrato, gastos por categoria e fatura do cartão são todos
/// calculados a partir de `transactions`. No protótipo HTML, `balance`,
/// `card.used` e as categorias de gasto eram campos independentes que
/// saíam de sincronia — um Pix não alterava o gráfico de gastos.
struct Ledger: Sendable {
    /// Saldo de abertura, antes da primeira transação registrada.
    var openingBalance: Money
    var transactions: [Transaction]

    init(openingBalance: Money, transactions: [Transaction] = []) {
        self.openingBalance = openingBalance
        self.transactions = transactions.sorted { $0.date > $1.date }
    }

    // MARK: Derivados

    var balance: Money {
        transactions.reduce(openingBalance) { $0 + $1.amount }
    }

    /// Ordenadas da mais recente para a mais antiga.
    var sorted: [Transaction] {
        transactions.sorted { $0.date > $1.date }
    }

    mutating func record(_ tx: Transaction) {
        transactions.insert(tx, at: 0)
        transactions.sort { $0.date > $1.date }
    }

    func transaction(id: UUID) -> Transaction? {
        transactions.first { $0.id == id }
    }

    // MARK: Agrupamento e filtro

    func grouped(_ items: [Transaction]) -> [TransactionGroup] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map {
            TransactionGroup(day: $0, items: buckets[$0]!.sorted { $0.date > $1.date })
        }
    }

    func transactions(in period: DateInterval) -> [Transaction] {
        sorted.filter { period.contains($0.date) }
    }

    // MARK: Totais do período

    func credits(in period: DateInterval) -> Money {
        transactions(in: period).filter(\.isCredit)
            .reduce(Money.zero) { $0 + $1.amount }
    }

    func debits(in period: DateInterval) -> Money {
        transactions(in: period).filter { !$0.isCredit }
            .reduce(Money.zero) { $0 + $1.amount.magnitude }
    }

    /// Gastos agrupados por categoria — deriva das transações de verdade.
    func spending(in period: DateInterval) -> [CategorySpend] {
        let debits = transactions(in: period)
            .filter { !$0.isCredit && $0.category.isSpending }
        let totals = Dictionary(grouping: debits, by: \.category)
            .mapValues { $0.reduce(Money.zero) { $0 + $1.amount.magnitude } }
        guard let peak = totals.values.max(), peak.amount > 0 else { return [] }
        return totals
            .sorted { $0.value > $1.value }
            .map { cat, total in
                CategorySpend(
                    category: cat,
                    total: total,
                    ratio: NSDecimalNumber(decimal: total.amount / peak.amount).doubleValue
                )
            }
    }

    func totalSpending(in period: DateInterval) -> Money {
        transactions(in: period)
            .filter { !$0.isCredit && $0.category.isSpending }
            .reduce(Money.zero) { $0 + $1.amount.magnitude }
    }

    /// Fatura em aberto do cartão de crédito: soma das compras no crédito
    /// desde o último pagamento de fatura.
    var creditInvoice: Money {
        var total = Money.zero
        for tx in sorted {   // do mais recente ao mais antigo
            if tx.title == Ledger.invoicePaymentTitle { break }
            if tx.method == .credito, !tx.isCredit { total += tx.amount.magnitude }
        }
        return total
    }

    static let invoicePaymentTitle = "Pagamento de fatura"
}

// MARK: - Períodos

extension DateInterval {
    /// Mês corrente, do primeiro instante ao último.
    static var currentMonth: DateInterval {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
        return DateInterval(start: start, end: end)
    }

    static func lastDays(_ n: Int) -> DateInterval {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: .now))!
        return DateInterval(start: start, end: .now.addingTimeInterval(86_400))
    }

    static var allTime: DateInterval {
        DateInterval(start: .distantPast, end: .distantFuture)
    }
}

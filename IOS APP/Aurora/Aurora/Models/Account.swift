import Foundation

struct User: Codable, Sendable, Hashable {
    var name: String
    var cpf: String
    var email: String
    var phone: String
    var agency: String = "0001"
    var account: String = "482917-3"

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var initials: String {
        name.split(separator: " ").prefix(2)
            .compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Cartão

struct Card: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case fisico, virtual
        var title: String { self == .fisico ? "Físico" : "Virtual" }
    }

    var kind: Kind = .fisico
    var isBlocked = false
    var limit: Money = 5_000
    var cashback: Money = 38.20
    /// Fatura em aberto. Deriva das compras no crédito, não é fixa.
    var invoiceDue: Date
    var number: String = "5412 7830 1195 2267"
    var cvv: String = "318"
    var expiry: String = "09/31"

    var maskedNumber: String { "•••• •••• •••• 4821" }

    func displayNumber(revealed: Bool) -> String {
        kind == .virtual && revealed ? number : maskedNumber
    }
}

// MARK: - Investimentos

struct InvestmentProduct: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var name: String
    var rate: String
    var liquidity: String
    /// Rendimento anual usado no simulador e no acúmulo de rendimento mock.
    var annualYield: Decimal
    var accent: String

    static let all: [InvestmentProduct] = [
        .init(id: "cdb", name: "CDB Aurora", rate: "110% do CDI",
              liquidity: "diária", annualYield: 0.1155, accent: "cyan"),
        .init(id: "selic", name: "Tesouro Selic 2029", rate: "Selic + 0,05%",
              liquidity: "D+1", annualYield: 0.1055, accent: "sky"),
        .init(id: "lci", name: "LCI Aurora 90 dias", rate: "93% do CDI, isento de IR",
              liquidity: "no vencimento", annualYield: 0.0977, accent: "violet"),
        .init(id: "fii", name: "Fundo Imobiliário AURA11", rate: "Renda variável",
              liquidity: "D+2", annualYield: 0.0920, accent: "amber"),
    ]

    static func find(_ id: String) -> InvestmentProduct {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Posição em um produto. Guarda o aportado para calcular rentabilidade —
/// o protótipo só tinha o valor atual, sem como saber o ganho.
struct Holding: Identifiable, Codable, Sendable, Hashable {
    var id: String            // == InvestmentProduct.id
    var invested: Money       // total aportado
    var current: Money        // valor atual com rendimento

    var product: InvestmentProduct { .find(id) }
    var earnings: Money { current - invested }

    var earningsPercent: Decimal {
        invested.isZero ? 0 : (earnings.amount / invested.amount) * 100
    }
}

// MARK: - Cofrinhos

struct Goal: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var name: String
    var saved: Money
    var target: Money
    var symbol: String = "banknote.fill"
    var deadline: Date?

    var progress: Double {
        guard target.amount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: saved.amount / target.amount).doubleValue)
    }

    var percentText: String { "\(Int(progress * 100))%" }
    var isComplete: Bool { saved >= target }
    var remaining: Money { max(.zero, target - saved) }
}

// MARK: - Empréstimo

/// Parcela de um empréstimo contratado. O protótipo creditava o dinheiro
/// e nunca gerava dívida — este tipo é o que fecha esse buraco.
struct Installment: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var number: Int
    var total: Int
    var amount: Money
    var dueDate: Date
    var paidAt: Date?

    var isPaid: Bool { paidAt != nil }
    var isOverdue: Bool { !isPaid && dueDate < .now }
    var label: String { "Parcela \(number) de \(total)" }
}

struct Loan: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var principal: Money
    var monthlyRate: Decimal
    var installments: [Installment]
    var contractedAt: Date

    var paidCount: Int { installments.filter(\.isPaid).count }
    var openInstallments: [Installment] { installments.filter { !$0.isPaid } }
    var outstanding: Money { openInstallments.reduce(Money.zero) { $0 + $1.amount } }
    var nextDue: Installment? { openInstallments.min { $0.dueDate < $1.dueDate } }
    var isSettled: Bool { openInstallments.isEmpty }

    /// Tabela Price: PMT = PV · i / (1 − (1+i)^−n)
    static func payment(principal: Money, monthlyRate i: Decimal, months n: Int) -> Money {
        guard n > 0, i > 0 else { return principal / Decimal(max(n, 1)) }
        let pv = NSDecimalNumber(decimal: principal.amount).doubleValue
        let rate = NSDecimalNumber(decimal: i).doubleValue
        let pmt = pv * rate / (1 - pow(1 + rate, -Double(n)))
        return Money(Decimal(pmt).rounded(2))
    }
}

// MARK: - Pix

struct PixKey: Identifiable, Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case cpf, celular, email, aleatoria
        var title: String {
            switch self {
            case .cpf: "CPF"
            case .celular: "Celular"
            case .email: "E-mail"
            case .aleatoria: "Aleatória"
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var value: String
    /// Valor mascarado para exibição (as chaves reais ficam ocultas).
    var masked: String
}

struct Contact: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var name: String
    var key: String
    var bank: String = "Banco Horizonte"

    var initials: String {
        name.split(separator: " ").prefix(2)
            .compactMap(\.first).map(String.init).joined().uppercased()
    }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

// MARK: - Utilitário

extension Decimal {
    /// Arredonda para `places` casas no modo bancário padrão de moeda.
    func rounded(_ places: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, places, .plain)
        return result
    }
}

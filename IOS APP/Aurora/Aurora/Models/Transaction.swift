import SwiftUI

/// Categoria de gasto. Dirige o gráfico de "Gastos" — que no protótipo
/// era uma lista fixa desconectada das transações.
enum Category: String, Codable, CaseIterable, Sendable, Identifiable {
    case moradia, mercado, restaurantes, transporte, assinaturas
    case saude, educacao, lazer, transferencia, investimento
    case salario, rendimento, credito, outros

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moradia: "Moradia"
        case .mercado: "Mercado"
        case .restaurantes: "Restaurantes"
        case .transporte: "Transporte"
        case .assinaturas: "Assinaturas"
        case .saude: "Saúde"
        case .educacao: "Educação"
        case .lazer: "Lazer"
        case .transferencia: "Transferências"
        case .investimento: "Investimentos"
        case .salario: "Salário"
        case .rendimento: "Rendimentos"
        case .credito: "Crédito"
        case .outros: "Outros"
        }
    }

    var symbol: String {
        switch self {
        case .moradia: "house.fill"
        case .mercado: "cart.fill"
        case .restaurantes: "fork.knife"
        case .transporte: "car.fill"
        case .assinaturas: "rectangle.stack.badge.play.fill"
        case .saude: "cross.case.fill"
        case .educacao: "book.fill"
        case .lazer: "ticket.fill"
        case .transferencia: "arrow.left.arrow.right"
        case .investimento: "chart.line.uptrend.xyaxis"
        case .salario: "briefcase.fill"
        case .rendimento: "arrow.up.right.circle.fill"
        case .credito: "creditcard.fill"
        case .outros: "square.grid.2x2.fill"
        }
    }

    /// Cor do espectro do design system. Usada só em dados — ícone da
    /// categoria e fatias de gráfico — com fundo tingido a 10%.
    var tint: Color {
        switch self {
        case .moradia: Theme.Spectrum.ice
        case .mercado: Theme.Spectrum.coral
        case .restaurantes: Theme.Spectrum.pink
        case .transporte: Theme.Spectrum.sky
        case .assinaturas: Theme.Spectrum.violet
        case .saude: Theme.Spectrum.cyan
        case .educacao: Theme.Spectrum.sky
        case .lazer: Theme.Spectrum.amber
        case .transferencia: Theme.Spectrum.cyan
        case .investimento: Theme.Spectrum.lime
        case .salario: Theme.Spectrum.lime
        case .rendimento: Theme.Spectrum.cyan
        case .credito: Theme.Spectrum.violet
        case .outros: Theme.Spectrum.ice
        }
    }

    /// Categorias que entram no orçamento mensal de despesas.
    var isSpending: Bool {
        switch self {
        case .salario, .rendimento, .credito, .investimento: false
        default: true
        }
    }
}

/// Meio pelo qual a transação aconteceu. Aparece no comprovante e no detalhe.
enum PaymentMethod: String, Codable, Sendable {
    case pix, debito, credito, boleto, ted, cofrinho, aplicacao, emprestimo, recarga

    var title: String {
        switch self {
        case .pix: "Pix"
        case .debito: "Cartão de débito"
        case .credito: "Cartão de crédito"
        case .boleto: "Boleto"
        case .ted: "TED"
        case .cofrinho: "Cofrinho"
        case .aplicacao: "Aplicação"
        case .emprestimo: "Empréstimo"
        case .recarga: "Recarga"
        }
    }

    var symbol: String {
        switch self {
        case .pix: "arrow.left.arrow.right.circle.fill"
        case .debito, .credito: "creditcard.fill"
        case .boleto: "barcode"
        case .ted: "building.columns.fill"
        case .cofrinho: "banknote.fill"
        case .aplicacao: "chart.line.uptrend.xyaxis"
        case .emprestimo: "hand.raised.fill"
        case .recarga: "antenna.radiowaves.left.and.right"
        }
    }
}

/// Uma linha do extrato. `date` é `Date` de verdade — o protótipo usava
/// strings ("Hoje", "24 set"), o que impedia filtro por período.
struct Transaction: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var date: Date
    var title: String
    var counterparty: String
    var amount: Money
    var category: Category
    var method: PaymentMethod
    /// Identificador do comprovante (E2E no caso do Pix).
    var authCode: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String,
        counterparty: String,
        amount: Money,
        category: Category,
        method: PaymentMethod,
        authCode: String = Transaction.newAuthCode()
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.counterparty = counterparty
        self.amount = amount
        self.category = category
        self.method = method
        self.authCode = authCode
    }

    var isCredit: Bool { amount.isPositive }

    /// Código de autenticação no formato E2E do Pix.
    static func newAuthCode() -> String {
        let hex = (0..<11).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        return "E" + hex.uppercased().prefix(31)
    }
}

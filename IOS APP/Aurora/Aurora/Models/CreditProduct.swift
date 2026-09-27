import SwiftUI

/// Produto de crédito, espelhando o catálogo da API. Cada modalidade tem
/// taxa, prazo e faixa de valor próprios.
struct CreditProduct: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String
    var monthlyRate: Decimal
    var maxMonths: Int
    var minAmount: Money
    var maxAmount: Money
    var symbol: String
    var accent: String

    var rateLabel: String {
        let pct = NSDecimalNumber(decimal: monthlyRate * 100).doubleValue
        return String(format: "%.2f%% a.m.", pct).replacingOccurrences(of: ".", with: ",")
    }

    var tint: Color { Theme.Spectrum.named(accent) }

    /// Catálogo local, igual ao da migration V9. O app pode exibir sem
    /// depender de uma chamada extra; o contrato envia o `id` para a API.
    static let all: [CreditProduct] = [
        .init(id: "pessoal", name: "Empréstimo pessoal",
              description: "Dinheiro na conta, sem burocracia. Sujeito a análise.",
              monthlyRate: 0.0249, maxMonths: 24, minAmount: 500, maxAmount: 20_000,
              symbol: "hand.raised.fill", accent: "violet"),
        .init(id: "consignado", name: "Crédito consignado",
              description: "Taxa menor com desconto em folha. Ideal para prazos longos.",
              monthlyRate: 0.0179, maxMonths: 48, minAmount: 1_000, maxAmount: 50_000,
              symbol: "building.columns.fill", accent: "cyan"),
        .init(id: "financiamento", name: "Financiamento",
              description: "Para veículo ou imóvel, em parcelas longas.",
              monthlyRate: 0.0199, maxMonths: 60, minAmount: 5_000, maxAmount: 200_000,
              symbol: "car.fill", accent: "sky"),
        .init(id: "antecipacao", name: "Antecipação de recebíveis",
              description: "Adiante valores a receber. Prazo curto, liberação imediata.",
              monthlyRate: 0.0349, maxMonths: 6, minAmount: 300, maxAmount: 15_000,
              symbol: "clock.arrow.circlepath", accent: "amber"),
    ]

    static func find(_ id: String) -> CreditProduct {
        all.first { $0.id == id } ?? all[0]
    }
}

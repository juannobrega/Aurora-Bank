import Foundation

/// Valor monetário em BRL. Usa `Decimal` — nunca `Double` — para que
/// somas de centavos não acumulem erro de ponto flutuante.
struct Money: Hashable, Codable, Sendable, Comparable {
    var amount: Decimal

    static let zero = Money(0)

    init(_ amount: Decimal) { self.amount = amount }

    /// Constrói a partir de centavos digitados no teclado numérico.
    init(cents: Int) { self.amount = Decimal(cents) / 100 }

    var cents: Int { NSDecimalNumber(decimal: amount * 100).intValue }
    var isPositive: Bool { amount > 0 }
    var isZero: Bool { amount == 0 }
    var magnitude: Money { Money(abs(amount)) }

    static func < (l: Money, r: Money) -> Bool { l.amount < r.amount }
    static func + (l: Money, r: Money) -> Money { Money(l.amount + r.amount) }
    static func - (l: Money, r: Money) -> Money { Money(l.amount - r.amount) }
    static func * (l: Money, r: Decimal) -> Money { Money(l.amount * r) }
    static func / (l: Money, r: Decimal) -> Money { Money(l.amount / r) }
    static func += (l: inout Money, r: Money) { l = l + r }
    static prefix func - (m: Money) -> Money { Money(-m.amount) }
}

extension Money: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    init(integerLiteral value: Int) { self.amount = Decimal(value) }
    init(floatLiteral value: Double) { self.amount = Decimal(value) }
}

// MARK: - Formatação

extension Money {
    private static let brl: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "BRL"
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    /// "R$ 4.280,55"
    var formatted: String {
        Self.brl.string(from: NSDecimalNumber(decimal: amount)) ?? "R$ 0,00"
    }

    /// "+ R$ 150,00" / "− R$ 87,40" (menos tipográfico, como no protótipo)
    var signed: String {
        (isPositive ? "+ " : "− ") + magnitude.formatted
    }

    /// Respeita o "ocultar saldo": devolve "••••" quando escondido.
    func formatted(hidden: Bool) -> String { hidden ? "••••" : formatted }
    func signed(hidden: Bool) -> String { hidden ? "••••" : signed }
}

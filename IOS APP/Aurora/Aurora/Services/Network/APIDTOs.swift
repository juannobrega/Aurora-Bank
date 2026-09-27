import Foundation

/// DTOs espelhando as respostas da API. Valores monetários chegam em
/// centavos (inteiro), como o backend define, e viram `Money` no mapeamento.
enum DTO {
    struct Tokens: Decodable { let accessToken, refreshToken, tokenType: String; let expiresIn: Int }

    struct User: Decodable {
        let id: String, fullName, maskedCpf, email, status: String
        var initials: String?
    }

    struct Snapshot: Decodable {
        let user: SnapshotUser
        let balanceCents: Int
        let card: Card
        let holdings: [Holding]
        let goals: [Goal]
        let recentTransactions: [Transaction]
        let monthSpendingCents: Int
        let monthlyBudgetCents: Int
        let creditScore: Int
        let unreadNotifications: Int
    }
    struct SnapshotUser: Decodable {
        let id, fullName, firstName, initials, maskedCpf, email, status: String
    }

    struct Card: Decodable {
        let id: String
        let kind: String
        let lastFour, expiry: String
        let creditLimit, invoice, available: MoneyDTO
        let blocked, contactless, onlinePurchases, international: Bool
        let invoiceDueDay: Int
    }
    struct MoneyDTO: Decodable { let amount: Decimal }

    struct Holding: Decodable {
        let productId, name, rateLabel, liquidity, accent: String
        let invested, current, earnings: MoneyDTO
    }

    struct Goal: Decodable {
        let id, name: String
        let savedCents, targetCents: Int
        let symbol: String
        let deadline: String?
        let progress: Double
    }

    struct Transaction: Decodable {
        let id, title, counterparty, category, method: String
        let isCredit: Bool
        let amountCents: Int
        let authCode: String
        let occurredAt: Date
    }

    struct StatementResponse: Decodable {
        let transactions: [Transaction]
        let creditsCents, debitsCents: Int
    }

    struct CategorySpend: Decodable { let category: String; let totalCents: Int }

    struct PixKey: Decodable { let id, kind, value: String }
    struct Contact: Decodable { let id, name, keyValue: String; let bank: String? }

    struct Product: Decodable {
        let id, name, rateLabel, liquidity, accent: String
    }

    struct Loan: Decodable {
        let id: String
        let principalCents: Int
        let installments: Int
        let paidCount: Int
        let outstandingCents: Int
        let schedule: [Installment]
    }
    struct Installment: Decodable {
        let id: String; let number: Int; let amountCents: Int
        let dueDate: String; let paid: Bool
    }

    struct Notification: Decodable {
        let id, kind, title, message: String
        let read: Bool
        let createdAt: Date
    }

    struct Simulation: Decodable {
        let payment, total, interest: MoneyDTO
        let rateLabel: String
    }
}

extension DTO.MoneyDTO { var money: Money { Money(amount) } }

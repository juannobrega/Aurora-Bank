import Foundation

/// Cliente da API real do Aurora. Substitui o MockAccountService: fala com
/// bank.pulsaz.com.br, faz login, carrega o snapshot e executa os fluxos.
///
/// O mapeamento DTO → domínio vive aqui, para que as views continuem
/// consumindo os mesmos tipos (`Money`, `Transaction`, `Goal`...) que já
/// usavam com o mock.
actor AuroraAPIClient {
    private let http: HTTPClient
    private let tokens: TokenStore

    init(tokens: TokenStore = TokenStore()) {
        self.tokens = tokens
        self.http = HTTPClient(tokens: tokens)
    }

    // MARK: - Onboarding

    struct SignUpBody: Encodable {
        let fullName, cpf, email, pin: String
        var phone: String?
    }

    func signUp(_ body: SignUpBody) async throws -> String {
        struct Res: Decodable { let id: String }
        let res = try await http.request(.post, "v1/onboarding/signup",
                                         body: body, authenticated: false, as: Res.self)
        return res.id
    }

    struct FaceEnrollBody: Encodable {
        let userId: String, features: [Float], algorithm: String
        let quality: Double, livenessPassed: Bool
    }

    func enrollFace(_ body: FaceEnrollBody) async throws {
        _ = try await http.request(.post, "v1/onboarding/face",
                                   body: body, authenticated: false, as: EmptyResponse.self)
    }

    // MARK: - Autenticação

    private struct DeviceBody: Encodable {
        let hardwareId, name: String
        var model, osVersion, publicKey: String?
    }

    private func device() -> DeviceBody {
        DeviceBody(hardwareId: APIConfig.hardwareId, name: Self.deviceName(),
                   model: nil, osVersion: nil, publicKey: nil)
    }

    func loginWithPin(cpf: String, pin: String) async throws {
        struct Body: Encodable { let cpf, pin: String; let device: DeviceBody }
        let res = try await http.request(.post, "v1/auth/login/pin",
            body: Body(cpf: cpf, pin: pin, device: device()),
            authenticated: false, as: DTO.Tokens.self)
        await storeTokens(res)
    }

    func loginWithFace(cpf: String, features: [Float], algorithm: String,
                       livenessPassed: Bool) async throws {
        struct Body: Encodable {
            let cpf: String; let features: [Float]; let algorithm: String
            let livenessPassed: Bool; let device: DeviceBody
        }
        let res = try await http.request(.post, "v1/auth/login/face",
            body: Body(cpf: cpf, features: features, algorithm: algorithm,
                       livenessPassed: livenessPassed, device: device()),
            authenticated: false, as: DTO.Tokens.self)
        await storeTokens(res)
    }

    func logout() async {
        if let refresh = await tokens.current()?.refreshToken {
            struct Body: Encodable { let refreshToken: String }
            _ = try? await http.request(.post, "v1/auth/logout",
                body: Body(refreshToken: refresh), authenticated: false, as: EmptyResponse.self)
        }
        await tokens.clear()
    }

    func hasSession() async -> Bool { await tokens.current() != nil }

    private func storeTokens(_ dto: DTO.Tokens) async {
        await tokens.save(.init(accessToken: dto.accessToken,
                                refreshToken: dto.refreshToken,
                                expiresAt: Date().addingTimeInterval(TimeInterval(dto.expiresIn))))
    }

    // MARK: - Snapshot

    func loadSnapshot() async throws -> DTO.Snapshot {
        try await http.request(.get, "v1/account/snapshot", as: DTO.Snapshot.self)
    }

    func pixKeys() async throws -> [DTO.PixKey] {
        try await http.request(.get, "v1/pix/keys", as: [DTO.PixKey].self)
    }
    func contacts() async throws -> [DTO.Contact] {
        try await http.request(.get, "v1/pix/contacts", as: [DTO.Contact].self)
    }
    func loans() async throws -> [DTO.Loan] {
        try await http.request(.get, "v1/credit/loans", as: [DTO.Loan].self)
    }

    // MARK: - Extrato

    func statement(from: Date? = nil, to: Date? = nil, credits: Bool? = nil,
                   search: String? = nil) async throws -> DTO.StatementResponse {
        var q: [String] = []
        let df = ISO8601DateFormatter(); df.formatOptions = [.withFullDate]
        if let from { q.append("from=\(df.string(from: from))") }
        if let to { q.append("to=\(df.string(from: to))") }
        if let credits { q.append("credits=\(credits)") }
        if let search, !search.isEmpty {
            q.append("search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        let path = "v1/statement" + (q.isEmpty ? "" : "?" + q.joined(separator: "&"))
        return try await http.request(.get, path, as: DTO.StatementResponse.self)
    }

    func spending() async throws -> [DTO.CategorySpend] {
        try await http.request(.get, "v1/statement/spending", as: [DTO.CategorySpend].self)
    }

    // MARK: - Fluxos (movem dinheiro)

    private struct Amount: Encodable { let amountCents: Int }

    func sendPix(pixKey: String, amountCents: Int, note: String?) async throws -> DTO.Transaction {
        struct Body: Encodable { let pixKey: String; let amountCents: Int; let note: String? }
        return try await http.request(.post, "v1/pix/send",
            body: Body(pixKey: pixKey, amountCents: amountCents, note: note), as: DTO.Transaction.self)
    }

    func payBoleto(line: String) async throws -> DTO.Transaction {
        struct Body: Encodable { let digitableLine: String }
        return try await http.request(.post, "v1/payments/boleto/pay",
            body: Body(digitableLine: line), as: DTO.Transaction.self)
    }

    func recharge(phone: String, amountCents: Int) async throws -> DTO.Transaction {
        struct Body: Encodable { let phone: String; let amountCents: Int }
        return try await http.request(.post, "v1/payments/recharge",
            body: Body(phone: phone, amountCents: amountCents), as: DTO.Transaction.self)
    }

    func invest(productId: String, amountCents: Int) async throws -> DTO.Transaction {
        try await http.request(.post, "v1/investments/\(productId)/invest",
            body: Amount(amountCents: amountCents), as: DTO.Transaction.self)
    }
    func redeem(productId: String, amountCents: Int) async throws -> DTO.Transaction {
        try await http.request(.post, "v1/investments/\(productId)/redeem",
            body: Amount(amountCents: amountCents), as: DTO.Transaction.self)
    }

    func depositGoal(id: String, amountCents: Int) async throws -> DTO.Transaction {
        try await http.request(.post, "v1/goals/\(id)/deposit",
            body: Amount(amountCents: amountCents), as: DTO.Transaction.self)
    }
    func withdrawGoal(id: String, amountCents: Int) async throws -> DTO.Transaction {
        try await http.request(.post, "v1/goals/\(id)/withdraw",
            body: Amount(amountCents: amountCents), as: DTO.Transaction.self)
    }

    func contractLoan(productId: String, amountCents: Int, months: Int) async throws -> DTO.Loan {
        struct Body: Encodable { let productId: String; let amountCents, months: Int }
        return try await http.request(.post, "v1/credit/loans",
            body: Body(productId: productId, amountCents: amountCents, months: months), as: DTO.Loan.self)
    }
    func payInvoice() async throws -> DTO.Transaction {
        try await http.request(.post, "v1/card/invoice/pay", as: DTO.Transaction.self)
    }

    // MARK: - Auxiliar

    private static func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Aurora iOS"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif

// MARK: - AccountServicing

/// Carrega tudo que a home precisa: snapshot + chaves + contatos + empréstimos,
/// em paralelo, e mapeia para o AccountSnapshot que o app já consome.
extension AuroraAPIClient: AccountServicing {
    func loadAccount() async throws -> AccountSnapshot {
        async let snapshot = loadSnapshot()
        async let keys = pixKeys()
        async let recentContacts = contacts()
        async let recentLoans = loans()

        return try await DTOMapper.accountSnapshot(
            snapshot, pixKeys: keys, contacts: recentContacts, loans: recentLoans)
    }
}

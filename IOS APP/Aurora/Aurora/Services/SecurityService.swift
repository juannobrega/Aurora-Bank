import Foundation
import LocalAuthentication
import Security

/// Guarda o PIN no Keychain e faz a autenticação biométrica de verdade.
/// No protótipo, `pinDone()` aceitava qualquer PIN e o Face ID era um timer.
protocol SecurityServicing: Sendable {
    func hasPIN() -> Bool
    func setPIN(_ pin: String) throws
    func verifyPIN(_ pin: String) -> Bool
    func clearPIN()
    var biometryType: LABiometryType { get }
    func authenticateWithBiometrics(reason: String) async throws -> Bool
}

enum SecurityError: LocalizedError {
    case keychain(OSStatus)
    case biometryUnavailable

    var errorDescription: String? {
        switch self {
        case .keychain: "Não foi possível salvar com segurança no aparelho."
        case .biometryUnavailable: "Biometria indisponível neste aparelho."
        }
    }
}

struct KeychainSecurityService: SecurityServicing {
    private let account = "br.com.aurora.bank.pin"
    private let service = "AuroraPIN"

    // MARK: PIN

    func hasPIN() -> Bool { readPIN() != nil }

    func setPIN(_ pin: String) throws {
        let data = Data(hashed(pin).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecurityError.keychain(status) }
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = readPIN() else { return false }
        // Comparação de tempo constante.
        let candidate = hashed(pin)
        guard stored.utf8.count == candidate.utf8.count else { return false }
        return zip(stored.utf8, candidate.utf8).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    func clearPIN() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func readPIN() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Derivação simples com sal fixo — suficiente para um app de demonstração
    /// com dados mockados. Um backend real nunca receberia o PIN em claro.
    private func hashed(_ pin: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in Array("aurora.salt.\(pin)".utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: Biometria

    var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    func authenticateWithBiometrics(reason: String) async throws -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Usar PIN"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw SecurityError.biometryUnavailable
        }
        return try await ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    }
}

extension LABiometryType {
    var title: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Biometria"
        }
    }
    var symbol: String {
        switch self {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }
}

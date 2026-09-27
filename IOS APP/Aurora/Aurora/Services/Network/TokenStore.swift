import Foundation
import Security

/// Guarda os tokens de sessão no Keychain — não em UserDefaults, que é
/// texto claro. O access token é curto; o refresh dura e não pode vazar.
actor TokenStore {
    private let service = "br.com.aurora.bank.tokens"

    struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private var cached: Tokens?

    func current() -> Tokens? {
        if let cached { return cached }
        cached = read()
        return cached
    }

    func save(_ tokens: Tokens) {
        cached = tokens
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    func clear() {
        cached = nil
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }

    private func read() -> Tokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        else { return nil }
        return tokens
    }
}

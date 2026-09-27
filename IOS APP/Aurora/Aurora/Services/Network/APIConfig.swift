import Foundation

/// Configuração do backend. A API real vive em bank.pulsaz.com.br; para
/// desenvolvimento local dá para apontar para o simulador.
enum APIConfig {
    /// Base da API. Trocável por variável de ambiente em testes.
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["AURORA_API_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://bank.pulsaz.com.br")!
    }()

    /// Identificador estável do aparelho (identifierForVendor no iOS).
    static var hardwareId: String {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
        #else
        return "simulator"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif

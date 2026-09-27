import Foundation

/// Escolhe entre o backend real e o mock. Um único ponto de troca para todo
/// o app — as views não sabem qual está ativo.
///
/// Por padrão usa a **API real** em bank.pulsaz.com.br. Para desenvolver com
/// dados locais sem servidor, rode com o argumento de lançamento
/// `-auroraUseMock`.
enum Backend {
    static var useMock: Bool {
        ProcessInfo.processInfo.arguments.contains("-auroraUseMock")
    }

    /// Cliente da API compartilhado — mantém a sessão (tokens) entre chamadas.
    static let api = AuroraAPIClient()

    static func accountService() -> any AccountServicing {
        useMock ? MockAccountService() : api
    }
}

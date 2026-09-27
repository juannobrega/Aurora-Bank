import Foundation

/// Erro vindo da API, no formato que o backend devolve.
struct APIError: LocalizedError, Decodable {
    let code: String
    let message: String
    var field: String?

    var errorDescription: String? { message }

    /// Erros de transporte, antes de haver resposta do servidor.
    static let noConnection = APIError(code: "SEM_CONEXAO",
        message: "Sem conexão. Verifique sua internet.")
    static let unexpected = APIError(code: "ERRO_INESPERADO",
        message: "Algo deu errado. Tente de novo.")

    static func http(_ status: Int) -> APIError {
        APIError(code: "HTTP_\(status)", message: "Erro no servidor (\(status)).")
    }
}

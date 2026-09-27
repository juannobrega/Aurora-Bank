import Foundation

/// Cliente HTTP do Aurora: monta a requisição, injeta o Bearer token,
/// renova o access token quando expira e traduz o erro do servidor.
actor HTTPClient {
    private let session: URLSession
    private let tokens: TokenStore
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Chamado quando a sessão expira de vez (refresh falhou) — o app
    /// desloga. Injetado pelo AppModel.
    var onSessionExpired: (@Sendable () -> Void)?

    init(tokens: TokenStore) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.tokens = tokens

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func setSessionExpiredHandler(_ handler: @escaping @Sendable () -> Void) {
        onSessionExpired = handler
    }

    enum Method: String { case get = "GET", post = "POST", put = "PUT",
                          patch = "PATCH", delete = "DELETE" }

    /// Requisição autenticada com corpo e resposta tipados.
    func request<Body: Encodable, Response: Decodable>(
        _ method: Method, _ path: String, body: Body? = nil,
        authenticated: Bool = true, as: Response.Type
    ) async throws -> Response {
        let data = try await perform(method, path, body: body, authenticated: authenticated)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.unexpected
        }
    }

    /// Sem corpo de requisição.
    func request<Response: Decodable>(
        _ method: Method, _ path: String,
        authenticated: Bool = true, as: Response.Type
    ) async throws -> Response {
        try await request(method, path, body: Optional<EmptyResponse>.none,
                          authenticated: authenticated, as: Response.self)
    }

    // MARK: - Núcleo

    private func perform<Body: Encodable>(
        _ method: Method, _ path: String, body: Body?, authenticated: Bool,
        isRetry: Bool = false
    ) async throws -> Data {
        var req = URLRequest(url: APIConfig.baseURL.appendingPathComponent(path))
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body { req.httpBody = try encoder.encode(body) }

        if authenticated, let token = await tokens.current()?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.noConnection
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.unexpected }

        // 401: tenta renovar uma vez e repetir.
        if http.statusCode == 401, authenticated, !isRetry {
            if await refresh() {
                return try await perform(method, path, body: body,
                                         authenticated: authenticated, isRetry: true)
            }
            onSessionExpired?()
            throw decodeError(data, status: 401)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw decodeError(data, status: http.statusCode)
        }
        return data
    }

    /// Renova o access token com o refresh. Devolve false se não deu.
    private func refresh() async -> Bool {
        guard let refreshToken = await tokens.current()?.refreshToken else { return false }
        struct Req: Encodable { let refreshToken: String }
        struct Res: Decodable { let accessToken, refreshToken: String; let expiresIn: Int }

        var req = URLRequest(url: APIConfig.baseURL.appendingPathComponent("v1/auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? encoder.encode(Req(refreshToken: refreshToken))

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let res = try? decoder.decode(Res.self, from: data)
        else { return false }

        await tokens.save(.init(accessToken: res.accessToken,
                                refreshToken: res.refreshToken,
                                expiresAt: Date().addingTimeInterval(TimeInterval(res.expiresIn))))
        return true
    }

    private func decodeError(_ data: Data, status: Int) -> APIError {
        (try? decoder.decode(APIError.self, from: data)) ?? .http(status)
    }
}

/// Placeholder para requisições/respostas vazias.
struct EmptyResponse: Codable {}

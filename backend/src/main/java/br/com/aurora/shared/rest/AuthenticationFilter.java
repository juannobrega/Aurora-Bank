package br.com.aurora.shared.rest;

import br.com.aurora.identity.auth.TokenService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Set;
import java.util.UUID;

/**
 * Lê o Bearer token e coloca o {@link CurrentUser} na requisição.
 *
 * <p>Rotas públicas são uma lista explícita: qualquer rota nova nasce
 * protegida, que é o padrão seguro.
 */
@Component
@Order(1)
public class AuthenticationFilter extends OncePerRequestFilter {

    public static final String ATTRIBUTE = "aurora.currentUser";

    private static final Set<String> PUBLIC_PREFIXES = Set.of(
            "/v1/onboarding",      // criar conta e cadastrar rosto
            "/v1/auth/login",
            "/v1/auth/refresh",
            "/admin",   // protegido pela própria X-Admin-Key, não pelo JWT
            "/docs", "/swagger-ui", "/v3/api-docs", "/actuator/health");

    private final TokenService tokens;
    private final ObjectMapper json;

    public AuthenticationFilter(TokenService tokens, ObjectMapper json) {
        this.tokens = tokens;
        this.json = json;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain)
            throws ServletException, IOException {

        if (isPublic(request.getRequestURI())) {
            chain.doFilter(request, response);
            return;
        }

        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith("Bearer ")) {
            unauthorized(response, "Informe o token de acesso.");
            return;
        }

        var authenticated = tokens.verify(header.substring(7));
        if (authenticated.isEmpty()) {
            unauthorized(response, "Sua sessão expirou. Entre novamente.");
            return;
        }

        var user = authenticated.get();
        request.setAttribute(ATTRIBUTE, new CurrentUser(
                user.userId(), user.deviceId(), user.sessionId(), user.level()));
        chain.doFilter(request, response);
    }

    private boolean isPublic(String uri) {
        return PUBLIC_PREFIXES.stream().anyMatch(uri::startsWith);
    }

    private void unauthorized(HttpServletResponse response, String message)
            throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        json.writeValue(response.getWriter(),
                ApiError.of("SESSAO_EXPIRADA", message, UUID.randomUUID().toString()));
    }
}

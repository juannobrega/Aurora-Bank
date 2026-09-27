package br.com.aurora.shared.rest;

import br.com.aurora.identity.auth.TokenService;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;

import java.util.UUID;

/** Quem está chamando, extraído do token pelo filtro de autenticação. */
public record CurrentUser(UUID userId, UUID deviceId, UUID sessionId,
                          TokenService.AuthLevel level) {

    public boolean isStrong() {
        return level == TokenService.AuthLevel.STRONG;
    }

    /**
     * Exige autenticação forte para operações que movem dinheiro.
     *
     * <p>Uma sessão restaurada por refresh volta em BASIC: ler saldo e
     * extrato pode, mas transferir exige confirmar PIN ou rosto de novo.
     * Sem esta checagem, um refresh token roubado moveria dinheiro.
     */
    public void requireStrongAuth() {
        if (!isStrong()) {
            throw new DomainException(ErrorCode.AUTENTICACAO_FRACA);
        }
    }
}

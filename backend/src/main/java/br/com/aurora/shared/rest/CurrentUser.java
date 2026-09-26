package br.com.aurora.shared.rest;

import br.com.aurora.identity.auth.TokenService;

import java.util.UUID;

/** Quem está chamando, extraído do token pelo filtro de autenticação. */
public record CurrentUser(UUID userId, UUID deviceId, TokenService.AuthLevel level) {

    public boolean isStrong() {
        return level == TokenService.AuthLevel.STRONG;
    }
}

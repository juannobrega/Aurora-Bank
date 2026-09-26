package br.com.aurora.identity.ports;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/** Sessões ativas. Logout revoga a sessão, não o vínculo do aparelho. */
public interface SessionRepository {

    void create(UUID sessionId, UUID userId, UUID deviceId,
                String refreshTokenHash, Instant expiresAt);

    Optional<ActiveSession> findByRefreshHash(String refreshTokenHash);

    void revoke(UUID sessionId, String reason);

    /** Encerra todas as sessões do usuário — exceto, opcionalmente, uma. */
    int revokeAllFor(UUID userId, UUID exceptSessionId, String reason);

    record ActiveSession(UUID id, UUID userId, UUID deviceId, Instant expiresAt) {}
}

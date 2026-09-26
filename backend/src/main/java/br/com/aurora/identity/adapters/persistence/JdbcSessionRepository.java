package br.com.aurora.identity.adapters.persistence;

import br.com.aurora.identity.ports.SessionRepository;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Repository
public class JdbcSessionRepository implements SessionRepository {

    private final NamedParameterJdbcTemplate jdbc;

    public JdbcSessionRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void create(UUID sessionId, UUID userId, UUID deviceId,
                       String refreshTokenHash, Instant expiresAt) {
        jdbc.update("""
            INSERT INTO sessions (id, user_id, device_id, refresh_token_hash, expires_at)
            VALUES (:id, :user, :device, :hash, :expires)
            """,
            new MapSqlParameterSource()
                .addValue("id", sessionId)
                .addValue("user", userId)
                .addValue("device", deviceId)
                .addValue("hash", refreshTokenHash)
                .addValue("expires", Timestamp.from(expiresAt)));
    }

    @Override
    public Optional<ActiveSession> findByRefreshHash(String hash) {
        return jdbc.query("""
            SELECT id, user_id, device_id, expires_at
              FROM sessions
             WHERE refresh_token_hash = :hash
               AND revoked_at IS NULL
               AND expires_at > now()
            """,
            Map.of("hash", hash),
            (rs, n) -> new ActiveSession(
                    rs.getObject("id", UUID.class),
                    rs.getObject("user_id", UUID.class),
                    rs.getObject("device_id", UUID.class),
                    rs.getTimestamp("expires_at").toInstant()))
            .stream().findFirst();
    }

    @Override
    public void revoke(UUID sessionId, String reason) {
        jdbc.update("""
            UPDATE sessions SET revoked_at = now(), revoked_reason = :reason
             WHERE id = :id AND revoked_at IS NULL
            """, Map.of("id", sessionId, "reason", reason));
    }

    @Override
    public int revokeAllFor(UUID userId, UUID exceptSessionId, String reason) {
        return jdbc.update("""
            UPDATE sessions SET revoked_at = now(), revoked_reason = :reason
             WHERE user_id = :user AND revoked_at IS NULL
               AND (:except::uuid IS NULL OR id <> :except::uuid)
            """,
            new MapSqlParameterSource()
                .addValue("user", userId)
                .addValue("except", exceptSessionId)
                .addValue("reason", reason));
    }
}

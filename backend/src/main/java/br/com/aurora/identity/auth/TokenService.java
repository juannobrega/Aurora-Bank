package br.com.aurora.identity.auth;

import br.com.aurora.shared.time.AuroraClock;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;

/**
 * Emissão e verificação de tokens.
 *
 * <p>O access token é curto (15 min) e carrega a identidade; o refresh é
 * longo, opaco e guardado como hash no banco — assim um vazamento do banco
 * não permite forjar sessão, e revogar é apagar a linha.
 */
@Component
public class TokenService {

    public static final Duration ACCESS_TTL  = Duration.ofMinutes(15);
    public static final Duration REFRESH_TTL = Duration.ofDays(30);

    private final SecretKey key;
    private final AuroraClock clock;
    private final SecureRandom random = new SecureRandom();

    public TokenService(@Value("${aurora.jwt.secret}") String secret, AuroraClock clock) {
        byte[] raw = Base64.getDecoder().decode(secret);
        if (raw.length < 32) {
            throw new IllegalStateException(
                    "aurora.jwt.secret precisa de ao menos 32 bytes em Base64.");
        }
        this.key = Keys.hmacShaKeyFor(raw);
        this.clock = clock;
    }

    /**
     * Token de acesso com usuário, dispositivo, sessão e nível de garantia.
     * A sessão vai junto para que "encerrar as outras" saiba qual poupar.
     */
    public String issueAccessToken(UUID userId, UUID deviceId, UUID sessionId,
                                   AuthLevel level) {
        var now = clock.instant();
        return Jwts.builder()
                .subject(userId.toString())
                .claim("did", deviceId.toString())
                .claim("sid", sessionId.toString())
                .claim("aal", level.name())
                .issuedAt(java.util.Date.from(now))
                .expiration(java.util.Date.from(now.plus(ACCESS_TTL)))
                .signWith(key)
                .compact();
    }

    public Optional<AuthenticatedUser> verify(String token) {
        try {
            Claims c = Jwts.parser().verifyWith(key).build()
                    .parseSignedClaims(token).getPayload();
            return Optional.of(new AuthenticatedUser(
                    UUID.fromString(c.getSubject()),
                    UUID.fromString(c.get("did", String.class)),
                    UUID.fromString(c.get("sid", String.class)),
                    AuthLevel.valueOf(c.get("aal", String.class))));
        } catch (JwtException | IllegalArgumentException e) {
            return Optional.empty();   // expirado, adulterado ou malformado
        }
    }

    /** Refresh token opaco: 32 bytes aleatórios em Base64 URL-safe. */
    public String newRefreshToken() {
        byte[] raw = new byte[32];
        random.nextBytes(raw);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
    }

    public record AuthenticatedUser(UUID userId, UUID deviceId, UUID sessionId,
                                    AuthLevel level) {}

    /**
     * Nível de garantia da autenticação. Operações de dinheiro exigem
     * {@link #STRONG} — só PIN ou biometria recém-verificados servem.
     */
    public enum AuthLevel {
        /** Sessão restaurada por refresh token. Lê dados, não move dinheiro. */
        BASIC,
        /** PIN ou biometria conferidos nesta sessão. */
        STRONG
    }
}

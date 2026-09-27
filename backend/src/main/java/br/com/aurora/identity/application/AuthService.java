package br.com.aurora.identity.application;

import br.com.aurora.identity.auth.TokenService;
import br.com.aurora.identity.domain.*;
import br.com.aurora.identity.ports.SessionRepository;
import br.com.aurora.identity.ports.UserRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.UUID;

/**
 * Entrada e saída da conta.
 *
 * <p>O aparelho é vinculado no primeiro acesso e o vínculo sobrevive ao
 * logout: sair encerra a sessão, não o cadastro do dispositivo.
 */
@Service
public class AuthService {

    /** Tentativas erradas antes de bloquear temporariamente. */
    private static final int MAX_ATTEMPTS = 5;

    /** Quanto tempo a conta fica bloqueada depois de estourar o limite. */
    private static final Duration LOCK_DURATION = Duration.ofMinutes(15);

    private final UserRepository users;
    private final SessionRepository sessions;
    private final OnboardingService onboarding;
    private final TokenService tokens;
    private final PasswordEncoder encoder;
    private final AuroraClock clock;

    public AuthService(UserRepository users, SessionRepository sessions,
                       OnboardingService onboarding, TokenService tokens,
                       PasswordEncoder encoder, AuroraClock clock) {
        this.users = users;
        this.sessions = sessions;
        this.onboarding = onboarding;
        this.tokens = tokens;
        this.encoder = encoder;
        this.clock = clock;
    }

    public record DeviceInfo(String hardwareId, String name, String model,
                             String osVersion, String publicKey) {}

    public record Tokens(String accessToken, String refreshToken,
                         long expiresInSeconds, UUID sessionId) {}

    // ------------------------------------------------------------- login

    /**
     * Entrada por PIN.
     *
     * <p>Quatro dígitos são dez mil combinações: sem limite de tentativas,
     * um atacante varre tudo em minutos. O bloqueio temporário é o que
     * torna o espaço pequeno aceitável.
     */
    @Transactional
    public Tokens loginWithPin(String cpf, String pin, DeviceInfo deviceInfo) {
        var user = users.findByCpf(Cpf.normalize(cpf))
                .orElseThrow(() -> new DomainException(ErrorCode.PIN_INCORRETO));
        requireActive(user);

        var lock = users.lockState(user.id());
        if (lock.isLocked(clock.instant())) {
            throw new DomainException(ErrorCode.CONTA_BLOQUEADA,
                    "Tente novamente mais tarde ou entre com biometria.");
        }

        String hash = users.findPinHash(user.id())
                .orElseThrow(() -> new DomainException(ErrorCode.PIN_INCORRETO));

        if (!encoder.matches(pin, hash)) {
            users.registerFailedPin(user.id(), MAX_ATTEMPTS, LOCK_DURATION);
            throw new DomainException(ErrorCode.PIN_INCORRETO);
        }

        users.clearFailedPin(user.id());
        var device = registerOrUpdateDevice(user.id(), deviceInfo);
        return openSession(user.id(), device.id(), TokenService.AuthLevel.STRONG);
    }

    /** Entrada por rosto. Prova de vida é obrigatória. */
    @Transactional
    public Tokens loginWithFace(String cpf, float[] features, String algorithm,
                                boolean livenessPassed, DeviceInfo deviceInfo) {
        var user = users.findByCpf(Cpf.normalize(cpf))
                .orElseThrow(() -> new DomainException(ErrorCode.USUARIO_NAO_ENCONTRADO));
        requireActive(user);

        var device = registerOrUpdateDevice(user.id(), deviceInfo);

        var match = onboarding.verifyFace(new OnboardingService.FaceVerifyCommand(
                user.id(), features, algorithm, livenessPassed, device.id()));

        if (!match.matches()) {
            throw new DomainException(
                    match.livenessPassed() ? ErrorCode.ROSTO_NAO_CONFERE
                                           : ErrorCode.PROVA_DE_VIDA_REPROVADA);
        }
        return openSession(user.id(), device.id(), TokenService.AuthLevel.STRONG);
    }

    /**
     * Renova o acesso com o refresh token. A sessão volta em
     * {@link TokenService.AuthLevel#BASIC}: ler dados pode, mover dinheiro
     * exige PIN ou biometria de novo.
     */
    @Transactional
    public Tokens refresh(String refreshToken) {
        var session = sessions.findByRefreshHash(sha256(refreshToken))
                .orElseThrow(() -> new DomainException(ErrorCode.SESSAO_EXPIRADA));

        // Rotaciona: o token usado deixa de valer, para que um refresh
        // roubado só sirva uma vez.
        sessions.revoke(session.id(), "rotacionado");
        users.touchDevice(session.deviceId());

        return openSession(session.userId(), session.deviceId(),
                TokenService.AuthLevel.BASIC);
    }

    /** Sai da conta. O dispositivo continua vinculado. */
    @Transactional
    public void logout(String refreshToken) {
        sessions.findByRefreshHash(sha256(refreshToken))
                .ifPresent(s -> sessions.revoke(s.id(), "logout"));
    }

    /**
     * Encerra as outras sessões, mantendo a atual.
     *
     * @param currentSessionId sessão a preservar — vem do token de quem
     *        chamou. Passar {@code null} encerraria a própria sessão junto.
     */
    @Transactional
    public int revokeOtherSessions(UUID userId, UUID currentSessionId) {
        return sessions.revokeAllFor(userId, currentSessionId, "encerrada pelo usuário");
    }

    @Transactional
    public void revokeDevice(UUID userId, UUID deviceId) {
        if (!users.updateDeviceStatus(userId, deviceId, DeviceStatus.REVOKED)) {
            throw new DomainException(ErrorCode.DISPOSITIVO_NAO_RECONHECIDO);
        }
        sessions.revokeAllFor(userId, null, "dispositivo revogado");
    }

    // ----------------------------------------------------------- internos

    private void requireActive(User user) {
        switch (user.status()) {
            case PENDING_KYC -> throw new DomainException(ErrorCode.KYC_PENDENTE);
            case BLOCKED, CLOSED -> throw new DomainException(ErrorCode.CONTA_BLOQUEADA);
            case ACTIVE -> { }
        }
    }

    private Device registerOrUpdateDevice(UUID userId, DeviceInfo info) {
        var existing = users.findDevice(userId, info.hardwareId());
        if (existing.isPresent()) {
            var device = existing.get();
            if (device.status() == DeviceStatus.REVOKED) {
                throw new DomainException(ErrorCode.DISPOSITIVO_REVOGADO);
            }
            users.touchDevice(device.id());
            return device;
        }
        var device = new Device(UUID.randomUUID(), userId, info.hardwareId(),
                info.name(), info.model(), info.osVersion(), info.publicKey(),
                DeviceStatus.TRUSTED, clock.instant(), clock.instant());
        users.saveDevice(device);
        return device;
    }

    private Tokens openSession(UUID userId, UUID deviceId, TokenService.AuthLevel level) {
        var sessionId = UUID.randomUUID();
        var refresh = tokens.newRefreshToken();
        var expires = clock.instant().plus(TokenService.REFRESH_TTL);

        sessions.create(sessionId, userId, deviceId, sha256(refresh), expires);

        return new Tokens(
                tokens.issueAccessToken(userId, deviceId, sessionId, level),
                refresh,
                TokenService.ACCESS_TTL.toSeconds(),
                sessionId);
    }

    /**
     * O refresh token é guardado como hash: vazamento do banco não permite
     * reutilizá-lo. SHA-256 basta aqui porque o token já é aleatório de 32
     * bytes — não há o que adivinhar, diferente de uma senha.
     */
    static String sha256(String value) {
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(
                    digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 indisponível", e);
        }
    }
}

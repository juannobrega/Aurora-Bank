package br.com.aurora.identity.application;

import br.com.aurora.identity.domain.*;
import br.com.aurora.identity.ports.UserRepository;
import br.com.aurora.ledger.domain.Account;
import br.com.aurora.ledger.domain.AccountType;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.shared.crypto.TemplateCipher;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

/**
 * Abertura de conta com validação facial.
 *
 * <p>A conta nasce em {@link UserStatus#PENDING_KYC} e só vira
 * {@code ACTIVE} depois que o rosto é cadastrado com prova de vida
 * aprovada — antes disso não movimenta dinheiro.
 */
@Service
public class OnboardingService {

    /** Abaixo disso a captura não serve para comparação confiável. */
    private static final double MIN_QUALITY = 0.65;

    private final UserRepository users;
    private final LedgerRepository ledger;
    private final TemplateCipher cipher;
    private final PasswordEncoder passwordEncoder;
    private final AuroraClock clock;

    public OnboardingService(UserRepository users, LedgerRepository ledger,
                             TemplateCipher cipher, PasswordEncoder passwordEncoder,
                             AuroraClock clock) {
        this.users = users;
        this.ledger = ledger;
        this.cipher = cipher;
        this.passwordEncoder = passwordEncoder;
        this.clock = clock;
    }

    public record SignUpCommand(String fullName, String cpf, String email,
                                String phone, LocalDate birthDate, String pin) {}

    /** Passo 1: dados pessoais e PIN. A conta ainda não pode transacionar. */
    @Transactional
    public User signUp(SignUpCommand cmd) {
        String cpf = Cpf.normalize(cmd.cpf());

        if (users.existsByCpf(cpf)) {
            throw new DomainException(ErrorCode.CPF_JA_CADASTRADO);
        }
        if (users.existsByEmail(cmd.email())) {
            throw new DomainException(ErrorCode.EMAIL_JA_CADASTRADO);
        }
        Pin.validate(cmd.pin());

        var user = new User(UUID.randomUUID(), cmd.fullName().trim(), cpf,
                cmd.email().toLowerCase().trim(), digitsOrNull(cmd.phone()),
                cmd.birthDate(), UserStatus.PENDING_KYC, clock.instant());

        users.save(user);
        // O PIN nunca é guardado em claro — só o hash, com sal por usuário.
        users.savePinHash(user.id(), passwordEncoder.encode(cmd.pin()));
        return user;
    }

    public record FaceEnrollCommand(UUID userId, float[] features, String algorithm,
                                    double quality, boolean livenessPassed) {}

    /**
     * Passo 2: cadastro facial. Aprovado, a conta é ativada e a conta
     * corrente é aberta no razão.
     */
    @Transactional
    public User enrollFace(FaceEnrollCommand cmd) {
        var user = users.findById(cmd.userId())
                .orElseThrow(() -> new DomainException(ErrorCode.USUARIO_NAO_ENCONTRADO));

        if (users.findActiveEnrollment(user.id()).isPresent()) {
            throw new DomainException(ErrorCode.BIOMETRIA_JA_CADASTRADA);
        }
        if (!cmd.livenessPassed()) {
            throw new DomainException(ErrorCode.PROVA_DE_VIDA_REPROVADA);
        }
        if (cmd.quality() < MIN_QUALITY) {
            throw new DomainException(ErrorCode.QUALIDADE_INSUFICIENTE);
        }

        var template = new FaceTemplate(cmd.features(), cmd.algorithm());
        var enrollment = new FaceEnrollment(UUID.randomUUID(), user.id(), template,
                cmd.quality(), true, clock.instant(), null);

        // Cifra antes de gravar: a imagem original nunca chega aqui, e o
        // template sai do processo já protegido.
        var sealed = cipher.seal(template.toBytes());
        users.saveEnrollment(enrollment, sealed.ciphertext(), sealed.nonce(), cmd.algorithm());

        // Rosto validado: a conta passa a existir de fato.
        users.updateStatus(user.id(), UserStatus.ACTIVE);
        ledger.saveAccount(new Account(UUID.randomUUID(), user.id(), user.id(),
                AccountType.CHECKING, "Conta corrente",
                br.com.aurora.shared.money.Money.ZERO, false));

        return new User(user.id(), user.fullName(), user.cpf(), user.email(),
                user.phone(), user.birthDate(), UserStatus.ACTIVE, user.createdAt());
    }

    public record FaceVerifyCommand(UUID userId, float[] features, String algorithm,
                                    boolean livenessPassed, UUID deviceId) {}

    /** Verifica um rosto contra o cadastro. Toda tentativa é auditada. */
    @Transactional
    public FaceMatch verifyFace(FaceVerifyCommand cmd) {
        var sealed = users.findActiveEnrollment(cmd.userId())
                .orElseThrow(() -> new DomainException(ErrorCode.BIOMETRIA_NAO_CADASTRADA));

        var stored = FaceTemplate.fromBytes(
                cipher.open(sealed.ciphertext(), sealed.nonce()), sealed.algorithm());
        var presented = new FaceTemplate(cmd.features(), cmd.algorithm());

        var match = FaceMatch.of(stored.distanceTo(presented), cmd.livenessPassed(),
                FaceMatch.DEFAULT_THRESHOLD);

        // Sucesso ou falha, a tentativa entra na trilha de auditoria.
        users.recordVerification(cmd.userId(), sealed.id(), match, cmd.deviceId());
        return match;
    }

    private static String digitsOrNull(String raw) {
        if (raw == null) return null;
        String d = raw.replaceAll("\\D", "");
        return d.isEmpty() ? null : d;
    }
}

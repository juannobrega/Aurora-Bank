package br.com.aurora.identity.adapters.rest;

import br.com.aurora.identity.application.OnboardingService;
import br.com.aurora.identity.domain.User;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.UUID;

/** Abertura de conta: dados pessoais, depois validação facial. */
@RestController
@RequestMapping("/v1/onboarding")
@Tag(name = "Onboarding", description = "Abertura de conta com validação facial")
public class OnboardingController {

    private final OnboardingService onboarding;

    public OnboardingController(OnboardingService onboarding) {
        this.onboarding = onboarding;
    }

    public record SignUpRequest(
            @NotBlank(message = "Informe seu nome completo.")
            @Pattern(regexp = "\\S+(\\s+\\S+)+", message = "Informe nome e sobrenome.")
            String fullName,

            @NotBlank(message = "Informe seu CPF.")
            String cpf,

            @NotBlank @Email(message = "E-mail inválido.")
            String email,

            String phone,
            LocalDate birthDate,

            @NotBlank
            @Pattern(regexp = "\\d{4}", message = "O PIN deve ter 4 dígitos.")
            String pin) {}

    public record UserResponse(UUID id, String fullName, String maskedCpf,
                               String email, String status, String initials) {
        static UserResponse of(User u) {
            return new UserResponse(u.id(), u.fullName(), u.maskedCpf(),
                    u.email(), u.status().name(), u.initials());
        }
    }

    @PostMapping("/signup")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Cria a conta",
               description = "A conta nasce em PENDING_KYC e só movimenta "
                           + "dinheiro depois da validação facial.")
    public UserResponse signUp(@Valid @RequestBody SignUpRequest r) {
        var user = onboarding.signUp(new OnboardingService.SignUpCommand(
                r.fullName(), r.cpf(), r.email(), r.phone(), r.birthDate(), r.pin()));
        return UserResponse.of(user);
    }

    public record FaceEnrollRequest(
            @NotNull UUID userId,
            @NotNull float[] features,
            @NotBlank String algorithm,
            @DecimalMin("0.0") @DecimalMax("1.0") double quality,
            boolean livenessPassed) {}

    @PostMapping("/face")
    @Operation(summary = "Cadastra o rosto e ativa a conta",
               description = "Recebe o template facial extraído no aparelho — "
                           + "nunca a fotografia. Exige prova de vida.")
    public UserResponse enrollFace(@Valid @RequestBody FaceEnrollRequest r) {
        var user = onboarding.enrollFace(new OnboardingService.FaceEnrollCommand(
                r.userId(), r.features(), r.algorithm(), r.quality(), r.livenessPassed()));
        return UserResponse.of(user);
    }
}

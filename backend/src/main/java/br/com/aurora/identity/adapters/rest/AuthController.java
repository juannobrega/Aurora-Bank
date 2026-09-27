package br.com.aurora.identity.adapters.rest;

import br.com.aurora.identity.application.AuthService;
import br.com.aurora.identity.domain.Device;
import br.com.aurora.identity.ports.UserRepository;
import br.com.aurora.shared.rest.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Entrada, saída e gestão de dispositivos. */
@RestController
@RequestMapping("/v1/auth")
@Tag(name = "Autenticação", description = "Login por PIN ou rosto, sessões e dispositivos")
public class AuthController {

    private final AuthService auth;
    private final UserRepository users;

    public AuthController(AuthService auth, UserRepository users) {
        this.auth = auth;
        this.users = users;
    }

    public record DeviceRequest(
            @NotBlank(message = "Informe o identificador do aparelho.")
            String hardwareId,
            @NotBlank String name,
            String model,
            String osVersion,
            String publicKey) {

        AuthService.DeviceInfo toInfo() {
            return new AuthService.DeviceInfo(hardwareId, name, model, osVersion, publicKey);
        }
    }

    public record PinLoginRequest(@NotBlank String cpf,
                                  @NotBlank @Pattern(regexp = "\\d{4}") String pin,
                                  @NotNull @Valid DeviceRequest device) {}

    public record FaceLoginRequest(@NotBlank String cpf,
                                   @NotNull float[] features,
                                   @NotBlank String algorithm,
                                   boolean livenessPassed,
                                   @NotNull @Valid DeviceRequest device) {}

    public record TokenResponse(String accessToken, String refreshToken,
                                String tokenType, long expiresIn) {
        static TokenResponse of(AuthService.Tokens t) {
            return new TokenResponse(t.accessToken(), t.refreshToken(),
                    "Bearer", t.expiresInSeconds());
        }
    }

    @PostMapping("/login/pin")
    @Operation(summary = "Entra com PIN")
    public TokenResponse loginWithPin(@Valid @RequestBody PinLoginRequest r) {
        return TokenResponse.of(auth.loginWithPin(r.cpf(), r.pin(), r.device().toInfo()));
    }

    @PostMapping("/login/face")
    @Operation(summary = "Entra com reconhecimento facial")
    public TokenResponse loginWithFace(@Valid @RequestBody FaceLoginRequest r) {
        return TokenResponse.of(auth.loginWithFace(r.cpf(), r.features(), r.algorithm(),
                r.livenessPassed(), r.device().toInfo()));
    }

    public record RefreshRequest(@NotBlank String refreshToken) {}

    @PostMapping("/refresh")
    @Operation(summary = "Renova o acesso",
               description = "A sessão volta em nível BASIC: para mover dinheiro "
                           + "é preciso confirmar PIN ou rosto de novo.")
    public TokenResponse refresh(@Valid @RequestBody RefreshRequest r) {
        return TokenResponse.of(auth.refresh(r.refreshToken()));
    }

    @PostMapping("/logout")
    @Operation(summary = "Sai da conta",
               description = "Encerra a sessão. O aparelho continua vinculado.")
    public void logout(@Valid @RequestBody RefreshRequest r) {
        auth.logout(r.refreshToken());
    }

    // ------------------------------------------------------- dispositivos

    public record DeviceResponse(UUID id, String name, String model,
                                 String status, Instant lastSeenAt, boolean current) {}

    @GetMapping("/devices")
    @Operation(summary = "Lista os aparelhos vinculados")
    public List<DeviceResponse> devices(CurrentUser me) {
        return users.listDevices(me.userId()).stream()
                .map(d -> toResponse(d, me.deviceId()))
                .toList();
    }

    @DeleteMapping("/devices/{deviceId}")
    @Operation(summary = "Revoga um aparelho")
    public void revokeDevice(CurrentUser me, @PathVariable UUID deviceId) {
        me.requireStrongAuth();
        auth.revokeDevice(me.userId(), deviceId);
    }

    public record RevokeSessionsResponse(int revoked) {}

    @PostMapping("/sessions/revoke-others")
    @Operation(summary = "Encerra as outras sessões")
    public RevokeSessionsResponse revokeOthers(CurrentUser me) {
        return new RevokeSessionsResponse(
                auth.revokeOtherSessions(me.userId(), me.sessionId()));
    }

    private static DeviceResponse toResponse(Device d, UUID currentDeviceId) {
        return new DeviceResponse(d.id(), d.name(), d.model(), d.status().name(),
                d.lastSeenAt(), d.id().equals(currentDeviceId));
    }
}

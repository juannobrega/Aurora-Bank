package br.com.aurora.identity.domain;

import java.time.Instant;
import java.util.UUID;

/**
 * Aparelho vinculado à conta.
 *
 * <p>O vínculo sobrevive ao logout: ao voltar, o mesmo aparelho é
 * reconhecido e basta PIN ou biometria — não se refaz o cadastro.
 */
public record Device(
        UUID id,
        UUID userId,
        String hardwareId,       // identifierForVendor do iOS
        String name,
        String model,
        String osVersion,
        String publicKey,        // chave pública do Secure Enclave
        DeviceStatus status,
        Instant lastSeenAt,
        Instant registeredAt
) {
    public boolean isTrusted() {
        return status == DeviceStatus.TRUSTED;
    }
}

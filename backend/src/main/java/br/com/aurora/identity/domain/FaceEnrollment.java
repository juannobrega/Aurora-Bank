package br.com.aurora.identity.domain;

import java.time.Instant;
import java.util.UUID;

/** Cadastro facial ativo de um usuário. */
public record FaceEnrollment(
        UUID id,
        UUID userId,
        FaceTemplate template,
        double quality,
        boolean livenessPassed,
        Instant enrolledAt,
        Instant revokedAt
) {
    public boolean isActive() { return revokedAt == null; }

    /** Compara um rosto apresentado com este cadastro. */
    public FaceMatch verify(FaceTemplate presented, boolean livenessPassed) {
        return FaceMatch.of(template.distanceTo(presented), livenessPassed,
                FaceMatch.DEFAULT_THRESHOLD);
    }
}

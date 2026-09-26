package br.com.aurora.identity.domain;

/**
 * Resultado de uma verificação facial.
 *
 * @param distance    distância entre o rosto apresentado e o cadastrado
 * @param threshold   limiar aceito; acima disso é outra pessoa
 */
public record FaceMatch(boolean matches, double distance, double threshold,
                        boolean livenessPassed, String failureReason) {

    /**
     * Limiar padrão. Mais baixo = mais rigoroso: reduz falso aceite
     * (deixar entrar quem não é) ao custo de mais falsa recusa.
     * Num banco, o erro caro é o falso aceite.
     */
    public static final double DEFAULT_THRESHOLD = 0.6;

    public static FaceMatch of(double distance, boolean livenessPassed, double threshold) {
        if (!livenessPassed) {
            return new FaceMatch(false, distance, threshold, false,
                    "Prova de vida não aprovada.");
        }
        boolean ok = distance <= threshold;
        return new FaceMatch(ok, distance, threshold, true,
                ok ? null : "O rosto não confere com o cadastrado.");
    }

    /** Similaridade em 0..1, para exibir ao usuário. */
    public double confidence() {
        return Math.max(0, 1 - (distance / (threshold * 2)));
    }
}

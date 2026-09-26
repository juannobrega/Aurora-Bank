package br.com.aurora.identity.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;

/**
 * Vetor de características extraído de um rosto.
 *
 * <p><b>Nunca é a fotografia.</b> Um template é uma lista de números que
 * descreve geometria facial; não permite reconstruir a imagem. A foto
 * original é descartada logo após a extração — é o que separa guardar
 * biometria de guardar um álbum de retratos.
 */
public record FaceTemplate(float[] features, String algorithm) {

    /** Dimensão típica de embedding facial. */
    public static final int DIMENSIONS = 128;

    public FaceTemplate {
        if (features == null || features.length != DIMENSIONS) {
            throw new DomainException(ErrorCode.BIOMETRIA_INVALIDA,
                    "Template deve ter " + DIMENSIONS + " dimensões.");
        }
        features = features.clone();       // defensivo: record não copia arrays
    }

    @Override
    public float[] features() {
        return features.clone();
    }

    /**
     * Distância euclidiana entre dois templates. Zero é idêntico; quanto
     * maior, mais diferentes os rostos.
     */
    public double distanceTo(FaceTemplate other) {
        if (!algorithm.equals(other.algorithm)) {
            throw new DomainException(ErrorCode.BIOMETRIA_INVALIDA,
                    "Templates de algoritmos diferentes não são comparáveis.");
        }
        double sum = 0;
        for (int i = 0; i < DIMENSIONS; i++) {
            double d = features[i] - other.features[i];
            sum += d * d;
        }
        return Math.sqrt(sum);
    }

    /** Serializa para gravar (antes de cifrar). */
    public byte[] toBytes() {
        var buffer = java.nio.ByteBuffer.allocate(DIMENSIONS * Float.BYTES);
        for (float f : features) buffer.putFloat(f);
        return buffer.array();
    }

    public static FaceTemplate fromBytes(byte[] bytes, String algorithm) {
        var buffer = java.nio.ByteBuffer.wrap(bytes);
        var features = new float[DIMENSIONS];
        for (int i = 0; i < DIMENSIONS; i++) features[i] = buffer.getFloat();
        return new FaceTemplate(features, algorithm);
    }
}

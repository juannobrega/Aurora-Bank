package br.com.aurora.identity;

import br.com.aurora.identity.domain.FaceMatch;
import br.com.aurora.identity.domain.FaceTemplate;
import br.com.aurora.shared.crypto.TemplateCipher;
import br.com.aurora.shared.error.DomainException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Random;

import static org.assertj.core.api.Assertions.*;

/** Biometria facial: comparação, limiar, prova de vida e cifra em repouso. */
class FaceBiometryTest {

    private static final String ALGO = "aurora-face-v1";

    /** Chave fixa de teste (32 bytes em Base64). */
    private final TemplateCipher cipher = new TemplateCipher(
            "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=");

    @Test
    @DisplayName("O mesmo rosto confere consigo mesmo")
    void mesmoRostoConfere() {
        var rosto = template(1);
        var match = FaceMatch.of(rosto.distanceTo(rosto), true, FaceMatch.DEFAULT_THRESHOLD);

        assertThat(match.matches()).isTrue();
        assertThat(match.distance()).isZero();
        assertThat(match.confidence()).isEqualTo(1.0);
    }

    @Test
    @DisplayName("Rosto de outra pessoa é recusado")
    void rostoDiferenteRecusado() {
        var match = FaceMatch.of(template(1).distanceTo(template(999)), true,
                FaceMatch.DEFAULT_THRESHOLD);

        assertThat(match.matches()).isFalse();
        assertThat(match.failureReason()).contains("não confere");
    }

    @Test
    @DisplayName("Pequena variação (ângulo, luz) ainda confere")
    void variacaoPequenaConfere() {
        var cadastrado = template(1);
        var apresentado = jitter(cadastrado, 0.01);   // ruído pequeno

        var match = FaceMatch.of(cadastrado.distanceTo(apresentado), true,
                FaceMatch.DEFAULT_THRESHOLD);

        assertThat(match.matches()).isTrue();
    }

    @Test
    @DisplayName("Sem prova de vida, nem rosto idêntico passa — barra a foto impressa")
    void semProvaDeVidaRecusa() {
        var rosto = template(1);
        var match = FaceMatch.of(rosto.distanceTo(rosto), false, FaceMatch.DEFAULT_THRESHOLD);

        assertThat(match.matches()).isFalse();
        assertThat(match.failureReason()).contains("Prova de vida");
    }

    @Test
    @DisplayName("Template com dimensão errada é recusado")
    void dimensaoErradaRecusada() {
        assertThatThrownBy(() -> new FaceTemplate(new float[10], ALGO))
                .isInstanceOf(DomainException.class);
        assertThatThrownBy(() -> new FaceTemplate(null, ALGO))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("Templates de algoritmos diferentes não são comparáveis")
    void algoritmosDiferentesNaoComparam() {
        var a = template(1);
        var b = new FaceTemplate(a.features(), "outro-algoritmo-v2");

        assertThatThrownBy(() -> a.distanceTo(b))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("algoritmos diferentes");
    }

    @Test
    @DisplayName("O template é mutável por fora? Não — record copia o array")
    void templateImutavel() {
        float[] original = new float[FaceTemplate.DIMENSIONS];
        original[0] = 1.0f;
        var t = new FaceTemplate(original, ALGO);

        original[0] = 99.0f;                 // tenta alterar por fora
        assertThat(t.features()[0]).isEqualTo(1.0f);

        t.features()[0] = 42.0f;             // tenta alterar o que saiu
        assertThat(t.features()[0]).isEqualTo(1.0f);
    }

    // ------------------------------------------------------------- cifra

    @Test
    @DisplayName("Template cifrado e decifrado volta idêntico")
    void cifraIdaEVolta() {
        var original = template(7);
        var sealed = cipher.seal(original.toBytes());
        var recuperado = FaceTemplate.fromBytes(
                cipher.open(sealed.ciphertext(), sealed.nonce()), ALGO);

        assertThat(recuperado.distanceTo(original)).isZero();
    }

    @Test
    @DisplayName("O texto cifrado não contém o template em claro")
    void cifraNaoVazaConteudo() {
        var original = template(7);
        var claro = original.toBytes();
        var sealed = cipher.seal(claro);

        assertThat(sealed.ciphertext()).isNotEqualTo(claro);
        // GCM acrescenta a tag de autenticação de 16 bytes.
        assertThat(sealed.ciphertext()).hasSize(claro.length + 16);
    }

    @Test
    @DisplayName("Cada cifragem usa nonce novo — reusar nonce quebraria o GCM")
    void nonceUnicoPorCifragem() {
        var claro = template(7).toBytes();
        var a = cipher.seal(claro);
        var b = cipher.seal(claro);

        assertThat(a.nonce()).isNotEqualTo(b.nonce());
        assertThat(a.ciphertext()).isNotEqualTo(b.ciphertext());
    }

    @Test
    @DisplayName("Template adulterado é detectado na decifragem")
    void adulteracaoDetectada() {
        var sealed = cipher.seal(template(7).toBytes());
        byte[] adulterado = sealed.ciphertext().clone();
        adulterado[0] ^= 0x01;                       // vira um bit

        assertThatThrownBy(() -> cipher.open(adulterado, sealed.nonce()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("decifrar");
    }

    @Test
    @DisplayName("Chave de tamanho errado é recusada na configuração")
    void chaveCurtaRecusada() {
        assertThatThrownBy(() -> new TemplateCipher("bXVpdG8tY3VydGE="))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("32 bytes");
    }

    // ------------------------------------------------------------ helpers

    /** Rosto sintético determinístico: a mesma semente dá o mesmo rosto. */
    private static FaceTemplate template(long seed) {
        var rnd = new Random(seed);
        var f = new float[FaceTemplate.DIMENSIONS];
        for (int i = 0; i < f.length; i++) f[i] = rnd.nextFloat();
        return new FaceTemplate(f, ALGO);
    }

    /** Mesma pessoa, captura ligeiramente diferente. */
    private static FaceTemplate jitter(FaceTemplate base, double amount) {
        var rnd = new Random(12345);
        var f = base.features();
        for (int i = 0; i < f.length; i++) {
            f[i] += (float) ((rnd.nextDouble() - 0.5) * amount);
        }
        return new FaceTemplate(f, base.algorithm());
    }
}

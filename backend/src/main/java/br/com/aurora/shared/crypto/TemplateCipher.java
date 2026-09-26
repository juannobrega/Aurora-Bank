package br.com.aurora.shared.crypto;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * Cifra o template biométrico em repouso, com AES-256-GCM.
 *
 * <p>Biometria é dado pessoal sensível (LGPD, Art. 5º, II). Guardar o
 * template em claro significaria que um vazamento do banco entrega o rosto
 * de todo mundo — e rosto, diferente de senha, não se troca.
 *
 * <p>GCM em vez de CBC porque é autenticado: além de cifrar, detecta
 * adulteração. Cada registro usa um nonce novo — reutilizar nonce em GCM
 * quebra a confidencialidade por completo.
 */
@Component
public class TemplateCipher {

    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final int NONCE_BYTES = 12;    // recomendado para GCM
    private static final int TAG_BITS = 128;

    private final SecretKeySpec key;
    private final SecureRandom random = new SecureRandom();

    public TemplateCipher(@Value("${aurora.crypto.template-key}") String base64Key) {
        byte[] raw = Base64.getDecoder().decode(base64Key);
        if (raw.length != 32) {
            throw new IllegalStateException(
                    "aurora.crypto.template-key deve ter 32 bytes (AES-256) em Base64; "
                    + "recebido: " + raw.length + " bytes.");
        }
        this.key = new SecretKeySpec(raw, "AES");
    }

    /** Texto cifrado e o nonce usado — ambos vão para o banco. */
    public record Sealed(byte[] ciphertext, byte[] nonce) {}

    public Sealed seal(byte[] plaintext) {
        try {
            byte[] nonce = new byte[NONCE_BYTES];
            random.nextBytes(nonce);
            var cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, nonce));
            return new Sealed(cipher.doFinal(plaintext), nonce);
        } catch (Exception e) {
            throw new IllegalStateException("Falha ao cifrar o template.", e);
        }
    }

    public byte[] open(byte[] ciphertext, byte[] nonce) {
        try {
            var cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, nonce));
            return cipher.doFinal(ciphertext);
        } catch (Exception e) {
            // Falha aqui significa chave errada ou dado adulterado.
            throw new IllegalStateException("Falha ao decifrar o template.", e);
        }
    }

    /** Gera uma chave nova — use para popular a configuração. */
    public static String generateKey() {
        byte[] raw = new byte[32];
        new SecureRandom().nextBytes(raw);
        return Base64.getEncoder().encodeToString(raw);
    }
}

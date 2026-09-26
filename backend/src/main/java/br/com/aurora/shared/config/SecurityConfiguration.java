package br.com.aurora.shared.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
public class SecurityConfiguration {

    /**
     * Argon2id para o PIN: com só quatro dígitos, o espaço de busca é de
     * dez mil combinações. O que impede a força bruta não é o tamanho do
     * PIN, é o custo de cada tentativa — daí um KDF caro de propósito,
     * somado ao bloqueio por tentativas no banco.
     */
    @Bean
    public PasswordEncoder passwordEncoder() {
        // saltLength, hashLength, paralelismo, memória (KiB), iterações
        return new Argon2PasswordEncoder(16, 32, 1, 1 << 14, 3);
    }
}

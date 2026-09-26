package br.com.aurora.shared.config;

import br.com.aurora.shared.time.AuroraClock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ClockConfiguration {

    /**
     * O tempo corre sozinho: este ambiente guarda dados reais e persistentes,
     * então adiantar o relógio corromperia o histórico.
     *
     * <p>O {@link AuroraClock} continua sendo injetado em vez de chamar
     * {@code Instant.now()} espalhado pelo código — é o que permite fixar o
     * tempo nos testes sem depender de quando eles rodam.
     */
    @Bean
    public AuroraClock clock() {
        return AuroraClock.system();
    }
}

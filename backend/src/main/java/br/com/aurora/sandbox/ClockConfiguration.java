package br.com.aurora.sandbox;

import br.com.aurora.shared.time.AuroraClock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;

@Configuration
public class ClockConfiguration {

    /**
     * No sandbox o relógio é controlável. Como {@link MutableClock} já é um
     * {@link AuroraClock}, ele atende tanto quem injeta a interface (todo o
     * domínio) quanto quem precisa do controle (os endpoints de sandbox) —
     * declarar um segundo bean só criaria ambiguidade.
     *
     * <p>Em produção o bean seria {@link AuroraClock#system()}, e nenhuma
     * regra de negócio precisa saber a diferença.
     */
    @Bean
    @Primary
    @Profile("!production")
    public MutableClock mutableClock() {
        return new MutableClock();
    }

    @Bean
    @Profile("production")
    public AuroraClock systemClock() {
        return AuroraClock.system();
    }
}

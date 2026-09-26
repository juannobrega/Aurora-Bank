package br.com.aurora.sandbox;

import br.com.aurora.shared.time.AuroraClock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
public class ClockConfiguration {

    /**
     * No sandbox o relógio é controlável. Em produção seria
     * {@link AuroraClock#system()} — e nenhuma regra de negócio precisa saber
     * a diferença, porque todas dependem apenas da interface.
     */
    @Bean
    @Profile("!production")
    public MutableClock mutableClock() {
        return new MutableClock();
    }

    @Bean
    @Profile("!production")
    public AuroraClock sandboxClock(MutableClock clock) {
        return clock;
    }

    @Bean
    @Profile("production")
    public AuroraClock systemClock() {
        return AuroraClock.system();
    }
}

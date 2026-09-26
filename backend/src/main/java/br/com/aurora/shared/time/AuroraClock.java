package br.com.aurora.shared.time;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

/**
 * O relógio do domínio.
 *
 * <p><b>Nenhuma regra de negócio chama {@code Instant.now()} diretamente.</b>
 * Num banco de sandbox o tempo é controlável: quem integra precisa de
 * "avance 30 dias e feche a fatura" sem esperar 30 dias. Isso só é possível
 * se todo acesso ao tempo passar por aqui.
 *
 * <p>Enxertar isso depois significaria revisitar cada arquivo do domínio —
 * por isso existe desde o primeiro commit.
 */
public interface AuroraClock {

    ZoneId BRAZIL = ZoneId.of("America/Sao_Paulo");

    /** Instante atual no mundo simulado. */
    Instant instant();

    /** Data atual no fuso de Brasília — vencimentos são data, não instante. */
    default LocalDate today() {
        return LocalDate.ofInstant(instant(), BRAZIL);
    }

    /** Adaptador para APIs que exigem {@link java.time.Clock}. */
    default Clock asJavaClock() {
        return Clock.fixed(instant(), BRAZIL);
    }

    /**
     * Relógio que acompanha o tempo real. Usado fora do sandbox e como
     * base para o relógio mutável.
     */
    static AuroraClock system() {
        return Instant::now;
    }

    /** Relógio parado num instante — para testes determinísticos. */
    static AuroraClock fixed(Instant at) {
        return () -> at;
    }

    /** Operações de controle, disponíveis apenas no modo sandbox. */
    interface Controllable extends AuroraClock {
        void advance(Duration duration);
        void set(Instant instant);
        void reset();
    }
}

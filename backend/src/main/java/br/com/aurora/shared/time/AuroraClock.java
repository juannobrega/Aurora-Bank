package br.com.aurora.shared.time;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

/**
 * O relógio do domínio.
 *
 * <p><b>Nenhuma regra de negócio chama {@code Instant.now()} diretamente.</b>
 * O tempo é uma dependência injetada como qualquer outra, o que permite
 * fixá-lo nos testes em vez de depender de quando eles rodam.
 *
 * <p>Em produção o tempo corre sozinho — este ambiente guarda dados reais
 * e persistentes, então não há relógio controlável.
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

    /** Relógio que acompanha o tempo real. */
    static AuroraClock system() {
        return Instant::now;
    }

    /** Relógio parado num instante — para testes determinísticos. */
    static AuroraClock fixed(Instant at) {
        return () -> at;
    }
}

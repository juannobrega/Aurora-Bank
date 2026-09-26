package br.com.aurora.shared;

import br.com.aurora.sandbox.MutableClock;
import br.com.aurora.shared.time.AuroraClock;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/** O relógio controlável: a capacidade que define um banco de sandbox. */
class MutableClockTest {

    private static final Instant BASE = Instant.parse("2026-09-26T12:00:00Z");

    @Test
    @DisplayName("Avançar 30 dias move a data do domínio")
    void avancaTrintaDias() {
        var clock = new MutableClock(AuroraClock.fixed(BASE));
        assertThat(clock.today()).isEqualTo(LocalDate.of(2026, 9, 26));

        clock.advance(Duration.ofDays(30));

        assertThat(clock.today()).isEqualTo(LocalDate.of(2026, 10, 26));
    }

    @Test
    @DisplayName("Fixar um instante para o relógio")
    void fixaInstante() {
        var clock = new MutableClock(AuroraClock.fixed(BASE));
        var alvo = Instant.parse("2026-12-31T23:59:00Z");

        clock.set(alvo);

        assertThat(clock.instant()).isEqualTo(alvo);
    }

    @Test
    @DisplayName("Avanços são cumulativos sobre um instante fixado")
    void avancosCumulativos() {
        var clock = new MutableClock(AuroraClock.fixed(BASE));
        clock.set(BASE);
        clock.advance(Duration.ofDays(1));
        clock.advance(Duration.ofHours(12));

        assertThat(clock.instant()).isEqualTo(Instant.parse("2026-09-28T00:00:00Z"));
    }

    @Test
    @DisplayName("Reset devolve o relógio ao tempo real")
    void resetVoltaAoReal() {
        var clock = new MutableClock(AuroraClock.fixed(BASE));
        clock.advance(Duration.ofDays(365));

        clock.reset();

        assertThat(clock.instant()).isEqualTo(BASE);
    }

    @Test
    @DisplayName("A data usa o fuso de Brasília, não UTC")
    void usaFusoDeBrasilia() {
        // 02:00 UTC do dia 27 ainda é dia 26 em São Paulo (UTC-3).
        var clock = new MutableClock(AuroraClock.fixed(Instant.parse("2026-09-27T02:00:00Z")));
        assertThat(clock.today()).isEqualTo(LocalDate.of(2026, 9, 26));
    }
}

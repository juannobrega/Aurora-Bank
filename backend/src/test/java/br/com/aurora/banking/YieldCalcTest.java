package br.com.aurora.banking;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Verifica a matemática do rendimento pró-rata isoladamente — a mesma
 * fórmula do YieldService, sem depender do job agendado nem do banco.
 */
class YieldCalcTest {

    private static final BigDecimal CDI = new BigDecimal("0.1015");
    private static final BigDecimal SECONDS_PER_YEAR = new BigDecimal("31557600");

    /** (1 + CDI)^t − 1, com t em fração de ano. */
    private static double factor(long seconds) {
        double t = new BigDecimal(seconds).divide(SECONDS_PER_YEAR, java.math.MathContext.DECIMAL64).doubleValue();
        return Math.pow(1 + CDI.doubleValue(), t) - 1;
    }

    @Test
    @DisplayName("Um ano cheio rende ~10,15% (100% do CDI)")
    void anoCheio() {
        double f = factor(31_557_600L);
        assertThat(f).isCloseTo(0.1015, org.assertj.core.data.Offset.offset(0.0001));
    }

    @Test
    @DisplayName("Um dia rende ~0,027% sobre o saldo")
    void umDia() {
        double f = factor(86_400L);
        // R$ 10.000 rendem alguns centavos ao dia.
        double yieldOn10k = 10_000 * f;
        assertThat(yieldOn10k).isBetween(2.5, 3.0);  // ~R$ 2,66/dia
    }

    @Test
    @DisplayName("Trinta dias sobre R$ 10.000 rende ~R$ 80")
    void trintaDias() {
        double yield = 10_000 * factor(30L * 86_400L);
        assertThat(yield).isBetween(78.0, 82.0);
    }

    @Test
    @DisplayName("Período zero não rende nada")
    void periodoZero() {
        assertThat(factor(0)).isZero();
    }
}

package br.com.aurora.shared.money;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

/**
 * Valor monetário em BRL.
 *
 * <p>Sempre {@link BigDecimal} com escala 2 — nunca {@code double}. Dinheiro
 * em ponto flutuante acumula erro de centavo, e num ledger double-entry esse
 * erro quebra a invariante de soma zero.
 *
 * <p>No transporte HTTP o valor trafega como inteiro de centavos
 * ({@link #cents()}), para não depender de como cada cliente serializa
 * decimais.
 */
public record Money(BigDecimal amount) implements Comparable<Money> {

    public static final Money ZERO = new Money(BigDecimal.ZERO);

    public Money {
        Objects.requireNonNull(amount, "amount");
        amount = amount.setScale(2, RoundingMode.HALF_EVEN);
    }

    public static Money of(String value) {
        return new Money(new BigDecimal(value));
    }

    public static Money ofCents(long cents) {
        return new Money(BigDecimal.valueOf(cents, 2));
    }

    /** Valor em centavos — a forma usada na API. */
    public long cents() {
        return amount.movePointRight(2).longValueExact();
    }

    public Money plus(Money other) {
        return new Money(amount.add(other.amount));
    }

    public Money minus(Money other) {
        return new Money(amount.subtract(other.amount));
    }

    public Money times(int factor) {
        return new Money(amount.multiply(BigDecimal.valueOf(factor)));
    }

    public Money negated() {
        return new Money(amount.negate());
    }

    public Money abs() {
        return new Money(amount.abs());
    }

    public boolean isZero()      { return amount.signum() == 0; }
    public boolean isPositive()  { return amount.signum() > 0; }
    public boolean isNegative()  { return amount.signum() < 0; }

    public boolean isGreaterThan(Money other)     { return compareTo(other) > 0; }
    public boolean isLessThan(Money other)        { return compareTo(other) < 0; }
    public boolean isGreaterOrEqual(Money other)  { return compareTo(other) >= 0; }

    @Override
    public int compareTo(Money other) {
        return amount.compareTo(other.amount);
    }

    @Override
    public String toString() {
        return "R$ " + amount.toPlainString();
    }
}

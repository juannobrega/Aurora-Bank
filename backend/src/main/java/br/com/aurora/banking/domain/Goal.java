package br.com.aurora.banking.domain;

import br.com.aurora.shared.money.Money;

import java.time.LocalDate;
import java.util.UUID;

/** Cofrinho. {@code saved} é o saldo da conta, não um campo armazenado. */
public record Goal(UUID id, UUID userId, UUID accountId, String name,
                   Money target, Money saved, String symbol, LocalDate deadline) {

    public double progress() {
        if (target.amount().signum() <= 0) return 0;
        return Math.min(1.0, saved.amount()
                .divide(target.amount(), 4, java.math.RoundingMode.HALF_EVEN)
                .doubleValue());
    }

    public Money remaining() {
        var diff = target.minus(saved);
        return diff.isNegative() ? Money.ZERO : diff;
    }

    public boolean isComplete() {
        return saved.isGreaterOrEqual(target);
    }
}

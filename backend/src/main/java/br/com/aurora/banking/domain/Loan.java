package br.com.aurora.banking.domain;

import br.com.aurora.shared.money.Money;

import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public record Loan(UUID id, UUID userId, UUID liabilityAccountId, Money principal,
                   BigDecimal monthlyRate, int installmentCount,
                   List<Installment> installments, Instant contractedAt) {

    public long paidCount() {
        return installments.stream().filter(Installment::isPaid).count();
    }

    public Money outstanding() {
        return installments.stream().filter(i -> !i.isPaid())
                .map(Installment::amount).reduce(Money.ZERO, Money::plus);
    }

    public Optional<Installment> nextDue() {
        return installments.stream().filter(i -> !i.isPaid())
                .min((a, b) -> a.dueDate().compareTo(b.dueDate()));
    }

    public boolean isSettled() {
        return installments.stream().allMatch(Installment::isPaid);
    }

    /**
     * Tabela Price: PMT = PV · i / (1 − (1+i)^−n).
     *
     * <p>Calculado em {@link BigDecimal} do começo ao fim — em {@code double}
     * a última parcela sairia alguns centavos errada.
     */
    public static Money payment(Money principal, BigDecimal monthlyRate, int months) {
        if (months <= 0) throw new IllegalArgumentException("months deve ser > 0");
        if (monthlyRate.signum() == 0) {
            return new Money(principal.amount()
                    .divide(BigDecimal.valueOf(months), 2, RoundingMode.HALF_EVEN));
        }
        var mc = new MathContext(20, RoundingMode.HALF_EVEN);
        BigDecimal onePlusI = BigDecimal.ONE.add(monthlyRate);
        BigDecimal factor = BigDecimal.ONE.divide(onePlusI.pow(months, mc), mc);
        BigDecimal denominator = BigDecimal.ONE.subtract(factor);
        return new Money(principal.amount().multiply(monthlyRate, mc)
                .divide(denominator, 2, RoundingMode.HALF_EVEN));
    }
}

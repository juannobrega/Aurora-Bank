package br.com.aurora.ledger.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;

import java.util.Objects;
import java.util.UUID;

/**
 * Uma perna do lançamento: quanto entrou ou saiu de uma conta.
 *
 * <p>{@code amount} é sempre positivo — ver {@link Direction}.
 */
public record Entry(UUID accountId, Direction direction, Money amount) {

    public Entry {
        Objects.requireNonNull(accountId, "accountId");
        Objects.requireNonNull(direction, "direction");
        Objects.requireNonNull(amount, "amount");
        if (!amount.isPositive()) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO);
        }
    }

    public static Entry debit(UUID accountId, Money amount) {
        return new Entry(accountId, Direction.DEBIT, amount);
    }

    public static Entry credit(UUID accountId, Money amount) {
        return new Entry(accountId, Direction.CREDIT, amount);
    }

    /** Contribuição algébrica ao saldo da conta: crédito soma, débito subtrai. */
    public Money signedAmount() {
        return direction == Direction.CREDIT ? amount : amount.negated();
    }
}

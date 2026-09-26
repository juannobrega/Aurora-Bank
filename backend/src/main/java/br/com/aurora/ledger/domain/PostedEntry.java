package br.com.aurora.ledger.domain;

import br.com.aurora.shared.money.Money;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Lançamento já gravado, com a ordem canônica e o contexto da transação. */
public record PostedEntry(
        UUID entryId,
        UUID transactionId,
        UUID accountId,
        Direction direction,
        Money amount,
        long sequence,
        Instant postedAt,
        LocalDate effectiveDate,
        String kind,
        String description
) {
    /** Contribuição ao saldo: crédito soma, débito subtrai. */
    public Money signedAmount() {
        return direction == Direction.CREDIT ? amount : amount.negated();
    }
}

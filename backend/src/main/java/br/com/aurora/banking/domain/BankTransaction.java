package br.com.aurora.banking.domain;

import br.com.aurora.shared.money.Money;

import java.time.Instant;
import java.util.UUID;

/**
 * Uma linha do extrato: o razão com o contexto de negócio que o usuário vê.
 *
 * <p>O valor aqui é absoluto; {@code isCredit} diz o sentido, igual ao que
 * o app faz com {@code Transaction.isCredit}.
 */
public record BankTransaction(
        UUID id,
        UUID userId,
        String title,
        String counterparty,
        TxCategory category,
        TxMethod method,
        boolean isCredit,
        Money amount,
        String authCode,
        Instant occurredAt,
        String note
) {
    /** Valor com sinal, do ponto de vista do dono da conta. */
    public Money signedAmount() {
        return isCredit ? amount : amount.negated();
    }
}

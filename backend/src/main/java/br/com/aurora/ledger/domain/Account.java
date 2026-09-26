package br.com.aurora.ledger.domain;

import br.com.aurora.shared.money.Money;

import java.util.UUID;

/**
 * Conta do razão. Pode ser do cliente (corrente, cofrinho, investimento) ou
 * interna do banco (liquidação, receita, funding).
 *
 * <p>Não tem campo de saldo: o saldo é derivado dos lançamentos.
 */
public record Account(
        UUID id,
        UUID tenantId,
        UUID ownerId,
        AccountType type,
        String name,
        Money openingBalance,
        boolean allowsNegative
) {
    public static Account of(UUID tenantId, UUID ownerId, AccountType type, String name) {
        return new Account(UUID.randomUUID(), tenantId, ownerId, type, name,
                Money.ZERO, !type.isCustomerAsset());
    }
}

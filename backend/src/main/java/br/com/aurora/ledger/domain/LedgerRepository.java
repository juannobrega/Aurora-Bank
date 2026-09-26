package br.com.aurora.ledger.domain;

import br.com.aurora.shared.money.Money;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Porta de persistência do razão. O domínio depende desta interface, nunca
 * de JPA ou de SQL — é o que permite testar as regras sem banco.
 */
public interface LedgerRepository {

    void saveAccount(Account account);

    Optional<Account> findAccount(UUID accountId);

    /**
     * Grava a transação e todas as suas pernas atomicamente.
     * A soma zero já foi garantida pelo construtor de
     * {@link LedgerTransaction}; o banco confirma de novo no COMMIT.
     */
    void append(LedgerTransaction transaction);

    /** Saldo derivado: abertura + créditos − débitos. */
    Money balanceOf(UUID accountId);

    /** Extrato da conta, do mais recente para o mais antigo. */
    List<PostedEntry> statement(UUID accountId, int limit);
}

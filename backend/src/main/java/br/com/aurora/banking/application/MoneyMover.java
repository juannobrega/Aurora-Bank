package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.ledger.domain.LedgerTransaction;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * Move dinheiro entre contas e registra o contexto de negócio.
 *
 * <p>Todo fluxo do app — Pix, boleto, cofrinho, investimento, empréstimo —
 * termina aqui. Centralizar tem um motivo concreto: a validação de saldo e
 * o registro no razão acontecem numa transação só, sempre da mesma forma.
 */
@Service
public class MoneyMover {

    private final LedgerRepository ledger;
    private final BankingRepository banking;
    private final AuroraClock clock;

    public MoneyMover(LedgerRepository ledger, BankingRepository banking,
                      AuroraClock clock) {
        this.ledger = ledger;
        this.banking = banking;
        this.clock = clock;
    }

    /** Descreve o movimento sem falar de débito e crédito. */
    public record Transfer(UUID userId, UUID fromAccount, UUID toAccount, Money amount,
                           String kind, String title, String counterparty,
                           TxCategory category, TxMethod method,
                           boolean isCreditForUser, String note) {}

    /**
     * Executa o movimento.
     *
     * @throws DomainException {@code SALDO_INSUFICIENTE} se a conta de
     *         origem não cobrir o valor — checado antes de gravar qualquer
     *         coisa, na mesma transação SQL.
     */
    @Transactional
    public BankTransaction move(Transfer t) {
        if (!t.amount().isPositive()) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO);
        }
        requireFunds(t.fromAccount(), t.amount());

        var ledgerTx = LedgerTransaction.transfer(
                t.userId(), t.kind(), t.counterparty(), clock.instant(),
                t.fromAccount(), t.toAccount(), t.amount());
        ledger.append(ledgerTx);

        var tx = new BankTransaction(
                ledgerTx.id(), t.userId(), t.title(), t.counterparty(),
                t.category(), t.method(), t.isCreditForUser(), t.amount(),
                ledgerTx.id().toString(), clock.instant(), t.note());
        banking.saveDetails(tx);
        return tx;
    }

    /**
     * Confere se a conta cobre o valor. Contas internas do banco
     * (liquidação, funding) podem ficar negativas — é assim que o
     * dinheiro entra no sistema.
     */
    private void requireFunds(UUID accountId, Money amount) {
        var account = ledger.findAccount(accountId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA));
        if (account.allowsNegative()) return;

        if (ledger.balanceOf(accountId).isLessThan(amount)) {
            throw new DomainException(ErrorCode.SALDO_INSUFICIENTE);
        }
    }
}

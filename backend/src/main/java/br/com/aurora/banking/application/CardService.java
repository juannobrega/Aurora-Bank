package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Cartão de crédito.
 *
 * <p>A fatura é o saldo da conta de passivo do cartão — não um campo que
 * alguém precisa lembrar de atualizar. Cada compra credita esse passivo;
 * pagar a fatura debita. Foi exatamente a incoerência que o protótipo
 * tinha, com {@code card.used} fixo enquanto as compras aconteciam.
 */
@Service
public class CardService {

    private final MoneyMover mover;
    private final BankingRepository banking;
    private final LedgerRepository ledger;

    public CardService(MoneyMover mover, BankingRepository banking,
                       LedgerRepository ledger) {
        this.mover = mover;
        this.banking = banking;
        this.ledger = ledger;
    }

    public record CardView(UUID id, String kind, String lastFour, String expiry,
                           Money creditLimit, Money invoice, Money available,
                           boolean blocked, boolean contactless,
                           boolean onlinePurchases, boolean international,
                           int invoiceDueDay) {}

    public CardView view(UUID userId) {
        var card = requireCard(userId);
        var invoice = ledger.balanceOf(card.liabilityAccountId());
        var limit = card.creditLimit();
        var available = limit.minus(invoice);
        return new CardView(card.id(), card.kind(), card.lastFour(), card.expiry(),
                limit, invoice, available.isNegative() ? Money.ZERO : available,
                card.blocked(), card.contactless(), card.onlinePurchases(),
                card.international(), card.invoiceDueDay());
    }

    /** Compra no crédito: não toca a conta corrente, engorda a fatura. */
    @Transactional
    public BankTransaction purchase(UUID userId, Money amount, String merchant,
                                    TxCategory category) {
        var card = requireCard(userId);
        if (card.blocked()) {
            throw new DomainException(ErrorCode.CONTA_BLOQUEADA, "Cartão bloqueado.");
        }
        var invoice = ledger.balanceOf(card.liabilityAccountId());
        if (invoice.plus(amount).isGreaterThan(card.creditLimit())) {
            throw new DomainException(ErrorCode.SALDO_INSUFICIENTE,
                    "Compra acima do limite disponível.");
        }
        return mover.move(new MoneyMover.Transfer(
                userId, banking.expenseAccount(), card.liabilityAccountId(), amount,
                "COMPRA_CREDITO", merchant, "Cartão de crédito",
                category, TxMethod.credito, false, null));
    }

    /** Paga a fatura com o saldo em conta. */
    @Transactional
    public BankTransaction payInvoice(UUID userId) {
        var card = requireCard(userId);
        var invoice = ledger.balanceOf(card.liabilityAccountId());
        if (!invoice.isPositive()) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "Não há fatura em aberto.");
        }
        // A fatura é o saldo CREDOR do passivo do cartão: cada compra o
        // credita. Pagar precisa DEBITAR esse passivo (zerando-o) e debitar
        // também a conta corrente — daí a perna de liquidação no meio, que
        // mantém a transação balanceada.
        mover.move(new MoneyMover.Transfer(
                userId, banking.checkingAccountOf(userId), banking.settlementAccount(),
                invoice, "PAGAMENTO_FATURA_SAIDA", "Pagamento de fatura",
                "Cartão Aurora", TxCategory.credito, TxMethod.credito, false, null));

        return mover.move(new MoneyMover.Transfer(
                userId, card.liabilityAccountId(), banking.settlementAccount(),
                invoice, "PAGAMENTO_FATURA", "Fatura quitada", "Cartão Aurora",
                TxCategory.credito, TxMethod.credito, false, null));
    }

    @Transactional
    public void updateSettings(UUID userId, Boolean blocked, Money limit,
                               Boolean contactless, Boolean online, Boolean international) {
        var card = requireCard(userId);
        var invoice = ledger.balanceOf(card.liabilityAccountId());
        var newLimit = limit == null ? card.creditLimit() : limit;

        if (newLimit.isLessThan(invoice)) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "O limite não pode ficar abaixo da fatura em aberto (" + invoice + ").");
        }
        banking.updateCard(card.id(),
                blocked == null ? card.blocked() : blocked,
                newLimit,
                contactless == null ? card.contactless() : contactless,
                online == null ? card.onlinePurchases() : online,
                international == null ? card.international() : international);
    }

    private BankingRepository.CardRow requireCard(UUID userId) {
        return banking.findCard(userId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Cartão não encontrado."));
    }
}

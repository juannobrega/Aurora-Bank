package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
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
    private final LoanService loans;

    public CardService(MoneyMover mover, BankingRepository banking,
                       LedgerRepository ledger, LoanService loans) {
        this.mover = mover;
        this.banking = banking;
        this.ledger = ledger;
        this.loans = loans;
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

    public List<BankingRepository.CardRow> list(UUID userId) {
        return banking.listCards(userId);
    }

    /**
     * Cria um cartão virtual: número e CVV próprios, mesma fatura do físico.
     * Serve para compras online sem expor o número do cartão físico.
     */
    @Transactional
    public BankingRepository.CardRow createVirtual(UUID userId) {
        var physical = requireCard(userId);
        var num = String.format("5412 %04d %04d %04d",
                (int)(Math.random()*10000), (int)(Math.random()*10000), (int)(Math.random()*10000));
        var cvv = String.format("%03d", (int)(Math.random()*1000));
        banking.createCard(userId, physical.liabilityAccountId(), "virtual",
                num.substring(num.length() - 4), physical.expiry(), num, cvv,
                physical.holderName());
        return banking.listCards(userId).stream()
                .filter(c -> c.cardNumber().equals(num)).findFirst().orElseThrow();
    }

    /** Compra no crédito pelo cartão principal. */
    @Transactional
    public BankTransaction purchase(UUID userId, Money amount, String merchant,
                                    TxCategory category) {
        return authorize(requireCard(userId), amount, merchant, category, false);
    }

    /**
     * Autoriza uma compra online informando número e CVV do cartão — o fluxo
     * de "digitar o código do cartão". Valida cartão, CVV, bloqueio e limite,
     * e lança a compra na fatura. É o papel que uma maquininha/gateway faria.
     */
    @Transactional
    public BankTransaction authorizeByNumber(UUID userId, String cardNumber, String cvv,
                                             Money amount, String merchant,
                                             TxCategory category) {
        var card = banking.findCardByNumber(cardNumber.trim())
                .filter(c -> c.userId().equals(userId))
                .orElseThrow(() -> new DomainException(ErrorCode.CARTAO_NAO_ENCONTRADO));
        if (!card.cvv().equals(cvv.trim())) {
            throw new DomainException(ErrorCode.CARTAO_CVV_INVALIDO);
        }
        if (!card.onlinePurchases()) {
            throw new DomainException(ErrorCode.COMPRA_ONLINE_BLOQUEADA);
        }
        return authorize(card, amount, merchant, category, true);
    }

    /** Lógica comum de autorização: bloqueio, limite, e lançamento na fatura. */
    private BankTransaction authorize(BankingRepository.CardRow card, Money amount,
                                      String merchant, TxCategory category, boolean online) {
        if (card.blocked()) {
            throw new DomainException(ErrorCode.CONTA_BLOQUEADA, "Cartão bloqueado.");
        }
        if (online && !card.onlinePurchases()) {
            throw new DomainException(ErrorCode.COMPRA_ONLINE_BLOQUEADA);
        }
        var invoice = ledger.balanceOf(card.liabilityAccountId());
        if (invoice.plus(amount).isGreaterThan(card.creditLimit())) {
            throw new DomainException(ErrorCode.LIMITE_CARTAO_EXCEDIDO,
                    "Compra acima do limite disponível.");
        }
        return mover.move(new MoneyMover.Transfer(
                card.userId(), banking.expenseAccount(), card.liabilityAccountId(), amount,
                "COMPRA_CREDITO", merchant,
                online ? "Compra online" : "Cartão de crédito",
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
        // credita, e pagar precisa DEBITÁ-LO. Ao mesmo tempo o dinheiro sai
        // da conta corrente. São três pernas numa transação só — fazer duas
        // transferências separadas gravaria dois débitos no extrato e
        // dobraria o gasto do mês.
        return mover.moveMany(new MoneyMover.MultiTransfer(
                userId,
                List.of(MoneyMover.Leg.debit(banking.checkingAccountOf(userId), invoice),
                        MoneyMover.Leg.debit(card.liabilityAccountId(), invoice),
                        MoneyMover.Leg.credit(banking.settlementAccount(),
                                              invoice.plus(invoice))),
                "PAGAMENTO_FATURA", "Pagamento de fatura", "Cartão Aurora",
                TxCategory.credito, TxMethod.credito, false, invoice, null));
    }

    /**
     * Parcela a fatura em aberto: quita a fatura atual e abre um contrato de
     * crédito equivalente. O app tinha o botão "Parcelar" sem nada por trás;
     * aqui o parcelamento vira dívida de verdade, com parcelas cobráveis.
     */
    @Transactional
    public java.util.UUID installInvoice(UUID userId, int months) {
        var card = requireCard(userId);
        var invoice = ledger.balanceOf(card.liabilityAccountId());
        if (!invoice.isPositive()) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "Não há fatura para parcelar.");
        }
        // Zera a fatura movendo o passivo do cartão para o funding (o banco
        // "adianta" a quitação). O openContract registra a dívida SEM
        // desembolsar — o cliente não recebe dinheiro, só passa a dever em
        // parcelas. Usar o contract completo depositaria a fatura na conta.
        mover.moveMany(new MoneyMover.MultiTransfer(
                userId,
                java.util.List.of(
                        MoneyMover.Leg.debit(card.liabilityAccountId(), invoice),
                        MoneyMover.Leg.credit(banking.fundingAccount(), invoice)),
                "FATURA_PARCELADA", "Parcelamento de fatura", "Cartão Aurora",
                TxCategory.credito, TxMethod.credito, false, invoice, null));

        return loans.openContract(userId, invoice, months).id();
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

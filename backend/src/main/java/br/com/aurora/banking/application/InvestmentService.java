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

/** Aplicação e resgate. Cada posição é uma conta no razão. */
@Service
public class InvestmentService {

    private final MoneyMover mover;
    private final BankingRepository banking;
    private final LedgerRepository ledger;

    public InvestmentService(MoneyMover mover, BankingRepository banking,
                             LedgerRepository ledger) {
        this.mover = mover;
        this.banking = banking;
        this.ledger = ledger;
    }

    public List<BankingRepository.InvestmentProduct> products() {
        return banking.listProducts();
    }

    public record Position(String productId, String name, String rateLabel,
                           String liquidity, String accent,
                           Money invested, Money current, Money earnings) {}

    public List<Position> positions(UUID userId) {
        return banking.listHoldings(userId).stream().map(h -> {
            var product = banking.findProduct(h.productId()).orElseThrow();
            var current = ledger.balanceOf(h.accountId());
            return new Position(product.id(), product.name(), product.rateLabel(),
                    product.liquidity(), product.accent(),
                    h.invested(), current, current.minus(h.invested()));
        }).toList();
    }

    @Transactional
    public BankTransaction invest(UUID userId, String productId, Money amount) {
        var product = banking.findProduct(productId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Produto não encontrado."));
        var holdingAccount = banking.ensureHoldingAccount(userId, productId);

        var tx = mover.move(new MoneyMover.Transfer(
                userId, banking.checkingAccountOf(userId), holdingAccount, amount,
                "APLICACAO", "Aplicação", product.name(),
                TxCategory.investimento, TxMethod.aplicacao, false, null));

        banking.addInvested(userId, productId, amount);
        return tx;
    }

    /**
     * Aplica (reinveste) o rendimento de uma posição: pega o quanto ela já
     * rendeu — valor atual menos o aportado — e registra como novo aporte,
     * sem tirar nada da conta corrente. O rendimento já estava na posição;
     * isto apenas o consolida como principal.
     */
    @Transactional
    public BankTransaction applyEarnings(UUID userId, String productId) {
        var product = banking.findProduct(productId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Produto não encontrado."));
        var holding = banking.listHoldings(userId).stream()
                .filter(h -> h.productId().equals(productId)).findFirst()
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Você não tem posição neste produto."));

        var current = ledger.balanceOf(holding.accountId());
        var earnings = current.minus(holding.invested());
        if (!earnings.isPositive()) {
            throw new DomainException(ErrorCode.SEM_RENDIMENTO,
                    "Esta posição ainda não tem rendimento para aplicar.");
        }
        // O dinheiro não se move — o rendimento já está na conta da posição.
        // Só reconhecemos o ganho como principal aportado.
        banking.addInvested(userId, productId, earnings);
        banking.notify(userId, "transaction", "Rendimento aplicado",
                earnings + " reinvestido em " + product.name());

        // Registro no extrato, com transação neutra (mesma conta dos dois lados
        // não vale; usa receita->posição de valor simbólico? Não: apenas
        // registramos como marco, sem mover saldo). Devolvemos a posição.
        return new BankTransaction(java.util.UUID.randomUUID(), userId,
                "Rendimento aplicado", product.name(), TxCategory.investimento,
                TxMethod.aplicacao, false, earnings,
                "APLIC" + java.util.UUID.randomUUID().toString().substring(0, 8).toUpperCase(),
                java.time.Instant.now(), null);
    }

    @Transactional
    public BankTransaction redeem(UUID userId, String productId, Money amount) {
        var product = banking.findProduct(productId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Produto não encontrado."));
        var holdingAccount = banking.ensureHoldingAccount(userId, productId);

        var tx = mover.move(new MoneyMover.Transfer(
                userId, holdingAccount, banking.checkingAccountOf(userId), amount,
                "RESGATE", "Resgate", product.name(),
                TxCategory.investimento, TxMethod.aplicacao, true, null));

        banking.addInvested(userId, productId, amount.negated());
        return tx;
    }
}

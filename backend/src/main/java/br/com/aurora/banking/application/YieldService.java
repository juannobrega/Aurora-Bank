package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * Rendimento automático do saldo em conta: 100% do CDI.
 *
 * <p>Como o tempo corre de verdade (não há relógio controlável), um job
 * credita o rendimento pró-rata do período decorrido desde o último cálculo.
 * A tabela {@code yield_accruals} guarda até quando cada conta já foi
 * remunerada, para nunca pagar o mesmo período duas vezes.
 */
@Service
public class YieldService {

    private static final Logger log = LoggerFactory.getLogger(YieldService.class);

    /** CDI anual de referência. 100% do CDI = esta taxa cheia. */
    private static final BigDecimal CDI_ANNUAL = new BigDecimal("0.1015");
    private static final BigDecimal SECONDS_PER_YEAR = new BigDecimal("31557600"); // 365.25d

    private final BankingRepository banking;
    private final LedgerRepository ledger;
    private final MoneyMover mover;
    private final AuroraClock clock;

    public YieldService(BankingRepository banking, LedgerRepository ledger,
                        MoneyMover mover, AuroraClock clock) {
        this.banking = banking;
        this.ledger = ledger;
        this.mover = mover;
        this.clock = clock;
    }

    /**
     * Roda de hora em hora. Num banco real seria fechamento diário; aqui,
     * mais frequente para o rendimento aparecer sem esperar o dia virar.
     */
    @Scheduled(fixedRate = 3_600_000, initialDelay = 60_000)
    public void accrueAll() {
        int count = 0;
        for (var accountId : banking.checkingAccountsToAccrue()) {
            try {
                if (accrue(accountId)) count++;
            } catch (Exception e) {
                log.warn("falha ao render conta {}: {}", accountId, e.getMessage());
            }
        }
        if (count > 0) log.info("rendimento creditado em {} conta(s)", count);
    }

    /**
     * Credita o rendimento de uma conta desde a última vez.
     *
     * <p>Juros compostos contínuos aproximados: saldo · (e^(r·t) − 1), com t
     * em fração de ano. Só credita a partir de um centavo, para não gerar
     * lançamentos de zero.
     */
    @Transactional
    public boolean accrue(UUID accountId) {
        var last = banking.lastAccrual(accountId);
        Instant now = clock.instant();
        Duration elapsed = Duration.between(last, now);
        if (elapsed.isNegative() || elapsed.isZero()) return false;

        Money balance = ledger.balanceOf(accountId);
        if (!balance.isPositive()) {
            banking.updateAccrual(accountId, now, Money.ZERO);
            return false;
        }

        var mc = new MathContext(20, RoundingMode.HALF_EVEN);
        BigDecimal t = new BigDecimal(elapsed.getSeconds()).divide(SECONDS_PER_YEAR, mc);
        // (1 + CDI)^t − 1, o fator de rendimento do período.
        double factor = Math.pow(1 + CDI_ANNUAL.doubleValue(), t.doubleValue()) - 1;
        Money yield = new Money(balance.amount()
                .multiply(BigDecimal.valueOf(factor), mc).setScale(2, RoundingMode.HALF_EVEN));

        if (!yield.isPositive()) return false;

        var userId = ledger.findAccount(accountId).map(a -> a.ownerId()).orElse(null);
        if (userId == null) return false;

        // O banco paga o rendimento a partir da sua conta de despesa.
        mover.move(new MoneyMover.Transfer(
                userId, banking.expenseAccount(), accountId, yield,
                "RENDIMENTO", "Rendimento", "100% do CDI",
                TxCategory.rendimento, TxMethod.aplicacao, true, null));

        banking.updateAccrual(accountId, now, yield);
        return true;
    }
}

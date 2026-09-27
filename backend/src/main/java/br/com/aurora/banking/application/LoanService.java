package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Empréstimo pessoal.
 *
 * <p>Contratar credita a conta <b>e</b> gera as parcelas. O protótipo
 * creditava o dinheiro sem nunca criar dívida — aqui o saldo devedor
 * existe como conta de passivo e as parcelas são cobráveis.
 */
@Service
public class LoanService {

    private static final BigDecimal MONTHLY_RATE = new BigDecimal("0.0249");

    private final MoneyMover mover;
    private final BankingRepository banking;
    private final AuroraClock clock;

    public LoanService(MoneyMover mover, BankingRepository banking, AuroraClock clock) {
        this.mover = mover;
        this.banking = banking;
        this.clock = clock;
    }

    public record Simulation(Money principal, int months, Money payment,
                             Money total, Money interest, String rateLabel) {}

    public Simulation simulate(Money principal, int months) {
        var payment = Loan.payment(principal, MONTHLY_RATE, months);
        var total = payment.times(months);
        return new Simulation(principal, months, payment, total,
                total.minus(principal), "2,49% a.m.");
    }

    /**
     * Empréstimo pessoal: cria a dívida <b>e</b> desembolsa o dinheiro na
     * conta corrente.
     */
    @Transactional
    public Loan contract(UUID userId, Money principal, int months) {
        var loan = openContract(userId, principal, months);

        mover.move(new MoneyMover.Transfer(
                userId, banking.fundingAccount(), banking.checkingAccountOf(userId),
                principal, "EMPRESTIMO_DESEMBOLSO", "Empréstimo pessoal",
                months + "x de " + loan.installments().get(0).amount(),
                TxCategory.credito, TxMethod.emprestimo, true, null));

        banking.notify(userId, "transaction", "Empréstimo aprovado",
                principal + " já está na sua conta");
        return loan;
    }

    /**
     * Cria o contrato e registra a dívida no passivo, <b>sem</b> desembolsar
     * dinheiro na conta.
     *
     * <p>Usado pelo parcelamento de fatura: ali o cliente não recebe nada —
     * a fatura, que já saiu do passivo do cartão, vira a dívida deste
     * contrato. Reusar o {@code contract} completo depositaria o valor da
     * fatura na conta corrente, dando dinheiro grátis.
     */
    @Transactional
    public Loan openContract(UUID userId, Money principal, int months) {
        if (months < 1 || months > 48) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "Escolha entre 1 e 48 parcelas.");
        }
        var liabilityAccount = banking.createLoanAccount(userId);
        var payment = Loan.payment(principal, MONTHLY_RATE, months);
        var today = clock.today();

        var installments = new ArrayList<Installment>(months);
        for (int n = 1; n <= months; n++) {
            installments.add(new Installment(UUID.randomUUID(), null, n, payment,
                    today.plusMonths(n), null));
        }

        var loan = new Loan(UUID.randomUUID(), userId, liabilityAccount, principal,
                MONTHLY_RATE, months, installments, clock.instant());
        banking.saveLoan(loan);

        // Reconhece a dívida no passivo. A contraparte é o funding: o banco
        // "adiantou" o valor (no empréstimo, para a conta; no parcelamento,
        // para quitar a fatura). Nenhum dinheiro toca a conta corrente aqui.
        mover.move(new MoneyMover.Transfer(
                userId, liabilityAccount, banking.fundingAccount(),
                payment.times(months), "EMPRESTIMO_DIVIDA", "Dívida contratada",
                "Saldo devedor", TxCategory.credito, TxMethod.emprestimo, false, null));

        return loan;
    }

    public List<Loan> list(UUID userId) {
        return banking.listLoans(userId);
    }

    @Transactional
    public BankTransaction payNextInstallment(UUID userId, UUID loanId) {
        var loan = banking.findLoan(userId, loanId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Contrato não encontrado."));
        var next = loan.nextDue()
                .orElseThrow(() -> new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                        "Este contrato já está quitado."));

        var tx = mover.move(new MoneyMover.Transfer(
                userId, banking.checkingAccountOf(userId), loan.liabilityAccountId(),
                next.amount(), "EMPRESTIMO_PARCELA", "Parcela de empréstimo",
                "Parcela " + next.number() + " de " + loan.installmentCount(),
                TxCategory.credito, TxMethod.emprestimo, false, null));

        banking.markInstallmentPaid(next.id());
        return tx;
    }
}

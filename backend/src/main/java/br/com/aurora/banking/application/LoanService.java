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

    public java.util.List<BankingRepository.CreditProduct> products() {
        return banking.creditProducts();
    }

    public Simulation simulate(String productId, Money principal, int months) {
        var product = requireProduct(productId);
        var rate = product.monthlyRate();
        var payment = Loan.payment(principal, rate, months);
        var total = payment.times(months);
        return new Simulation(principal, months, payment, total,
                total.minus(principal), formatRate(rate));
    }

    private BankingRepository.CreditProduct requireProduct(String id) {
        return banking.creditProduct(id)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Produto de crédito não encontrado."));
    }

    private static String formatRate(java.math.BigDecimal r) {
        return String.format("%.2f%% a.m.", r.doubleValue() * 100).replace(".", ",");
    }

    /**
     * Solicita um empréstimo pessoal. <b>Não desembolsa</b>: o contrato nasce
     * EM_ANALISE e só vira dinheiro quando o Manager aprova. As parcelas já
     * são calculadas, mas a dívida no razão só entra na aprovação.
     */
    @Transactional
    public Loan contract(UUID userId, String productId, Money principal, int months) {
        var product = requireProduct(productId);
        if (principal.isLessThan(product.minAmount()) || principal.isGreaterThan(product.maxAmount())) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "Valor fora da faixa deste produto ("
                    + product.minAmount() + " a " + product.maxAmount() + ").");
        }
        if (months < 1 || months > product.maxMonths()) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "Prazo máximo deste produto é " + product.maxMonths() + " parcelas.");
        }
        var loan = createPending(userId, productId, principal, months, product.monthlyRate());
        banking.notify(userId, "transaction", "Crédito em análise",
                "Seu pedido de " + principal + " (" + product.name() + ") está em análise.");
        return loan;
    }

    /**
     * Aprova um empréstimo em análise: reconhece a dívida no passivo e
     * desembolsa o principal na conta. Chamado pelo Manager.
     */
    @Transactional
    public Loan approve(UUID loanId, String decidedBy) {
        var loan = banking.findLoanById(loanId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Contrato não encontrado."));
        if (!loan.isUnderReview()) {
            throw new DomainException(ErrorCode.EMPRESTIMO_JA_DECIDIDO);
        }
        var payment = loan.installments().get(0).amount();

        // A dívida entra no passivo (contraparte funding) e o dinheiro sai
        // do funding para a conta do cliente. Nada disso aconteceu na análise.
        mover.move(new MoneyMover.Transfer(
                loan.userId(), loan.liabilityAccountId(), banking.fundingAccount(),
                payment.times(loan.installmentCount()), "EMPRESTIMO_DIVIDA",
                "Dívida contratada", "Saldo devedor", TxCategory.credito,
                TxMethod.emprestimo, false, null));
        mover.move(new MoneyMover.Transfer(
                loan.userId(), banking.fundingAccount(), banking.checkingAccountOf(loan.userId()),
                loan.principal(), "EMPRESTIMO_DESEMBOLSO", "Empréstimo pessoal",
                loan.installmentCount() + "x de " + payment, TxCategory.credito,
                TxMethod.emprestimo, true, null));

        banking.decideLoan(loanId, Loan.LoanState.ACTIVE, decidedBy, null);
        banking.notify(loan.userId(), "transaction", "Empréstimo aprovado",
                loan.principal() + " já está na sua conta.");
        return banking.findLoanById(loanId).orElseThrow();
    }

    /** Recusa um empréstimo em análise. */
    @Transactional
    public Loan reject(UUID loanId, String decidedBy, String note) {
        var loan = banking.findLoanById(loanId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Contrato não encontrado."));
        if (!loan.isUnderReview()) {
            throw new DomainException(ErrorCode.EMPRESTIMO_JA_DECIDIDO);
        }
        banking.decideLoan(loanId, Loan.LoanState.RECUSADO, decidedBy, note);
        banking.notify(loan.userId(), "transaction", "Empréstimo recusado",
                note == null || note.isBlank() ? "Seu pedido não foi aprovado."
                        : "Seu pedido não foi aprovado: " + note);
        return banking.findLoanById(loanId).orElseThrow();
    }

    /** Cria o contrato EM_ANALISE, com parcelas calculadas mas sem dívida. */
    @Transactional
    public Loan createPending(UUID userId, String productId, Money principal,
                              int months, java.math.BigDecimal rate) {
        var liabilityAccount = banking.createLoanAccount(userId);
        var payment = Loan.payment(principal, rate, months);
        var today = clock.today();

        var installments = new ArrayList<Installment>(months);
        for (int n = 1; n <= months; n++) {
            installments.add(new Installment(UUID.randomUUID(), null, n, payment,
                    today.plusMonths(n), null));
        }
        var loan = new Loan(UUID.randomUUID(), userId, liabilityAccount, principal,
                rate, months, Loan.LoanState.EM_ANALISE, installments, clock.instant());
        banking.saveLoan(loan, productId);
        return loan;
    }

    /**
     * Parcelamento de fatura: cria a dívida JÁ ATIVA e sem análise — a fatura
     * já foi movida do cartão, então é só reconhecer o parcelado. Não passa
     * pela esteira de aprovação, que é para empréstimo novo.
     */
    @Transactional
    public Loan openContractActive(UUID userId, Money principal, int months) {
        var loan = createPending(userId, "pessoal", principal, months,
                new java.math.BigDecimal("0.0199"));
        var payment = loan.installments().get(0).amount();
        mover.move(new MoneyMover.Transfer(
                userId, loan.liabilityAccountId(), banking.fundingAccount(),
                payment.times(months), "EMPRESTIMO_DIVIDA", "Dívida contratada",
                "Saldo devedor", TxCategory.credito, TxMethod.emprestimo, false, null));
        banking.decideLoan(loan.id(), Loan.LoanState.ACTIVE, "sistema", "parcelamento de fatura");
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

package br.com.aurora.banking.adapters.rest;

import br.com.aurora.banking.application.CardService;
import br.com.aurora.banking.application.InvestmentService;
import br.com.aurora.banking.domain.BankTransaction;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.identity.ports.UserRepository;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.rest.CurrentUser;
import br.com.aurora.shared.time.AuroraClock;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** Conta, saldo, extrato e o retrato inicial que o app carrega ao abrir. */
@RestController
@RequestMapping("/v1")
@Tag(name = "Conta", description = "Saldo, extrato e retrato da conta")
public class AccountController {

    private final LedgerRepository ledger;
    private final BankingRepository banking;
    private final UserRepository users;
    private final CardService cards;
    private final InvestmentService investments;
    private final AuroraClock clock;

    public AccountController(LedgerRepository ledger, BankingRepository banking,
                             UserRepository users, CardService cards,
                             InvestmentService investments, AuroraClock clock) {
        this.ledger = ledger;
        this.banking = banking;
        this.users = users;
        this.cards = cards;
        this.investments = investments;
        this.clock = clock;
    }

    // ------------------------------------------------------------ retrato

    public record Snapshot(UserView user, long balanceCents, CardService.CardView card,
                           List<InvestmentService.Position> holdings,
                           List<GoalView> goals, List<TxView> recentTransactions,
                           long monthSpendingCents, long monthlyBudgetCents,
                           int creditScore, int unreadNotifications) {}

    public record UserView(UUID id, String fullName, String firstName, String initials,
                           String maskedCpf, String email, String status) {}

    public record GoalView(UUID id, String name, long savedCents, long targetCents,
                           String symbol, LocalDate deadline, double progress) {}

    public record TxView(UUID id, String title, String counterparty, String category,
                         String method, boolean isCredit, long amountCents,
                         String authCode, Instant occurredAt) {
        static TxView of(BankTransaction t) {
            return new TxView(t.id(), t.title(), t.counterparty(), t.category().name(),
                    t.method().name(), t.isCredit(), t.amount().cents(),
                    t.authCode(), t.occurredAt());
        }
    }

    @GetMapping("/account/snapshot")
    @Operation(summary = "Retrato da conta",
               description = "Tudo que a tela inicial precisa, numa chamada só.")
    public Snapshot snapshot(CurrentUser me) {
        var user = users.findById(me.userId())
                .orElseThrow(() -> new DomainException(ErrorCode.USUARIO_NAO_ENCONTRADO));
        var checking = banking.checkingAccountOf(me.userId());
        var monthStart = clock.today().withDayOfMonth(1);
        // Carrega uma vez e reaproveita: o score consultava goals de novo.
        var goals = banking.listGoals(me.userId());
        var loans = banking.listLoans(me.userId());

        return new Snapshot(
                new UserView(user.id(), user.fullName(), user.firstName(),
                        user.initials(), user.maskedCpf(), user.email(),
                        user.status().name()),
                ledger.balanceOf(checking).cents(),
                cards.view(me.userId()),
                investments.positions(me.userId()),
                goals.stream()
                        .map(g -> new GoalView(g.id(), g.name(), g.saved().cents(),
                                g.target().cents(), g.symbol(), g.deadline(), g.progress()))
                        .toList(),
                banking.statement(me.userId(), null, null, null, null, 5)
                        .stream().map(TxView::of).toList(),
                banking.totalSpending(me.userId(), monthStart, clock.today()).cents(),
                MONTHLY_BUDGET.cents(),
                creditScore(me.userId(), goals, loans),
                (int) banking.listNotifications(me.userId()).stream()
                        .filter(n -> !n.read()).count());
    }

    @GetMapping("/account/balance")
    @Operation(summary = "Saldo disponível")
    public BalanceView balance(CurrentUser me) {
        var checking = banking.checkingAccountOf(me.userId());
        return new BalanceView(ledger.balanceOf(checking).cents(), "BRL");
    }

    public record BalanceView(long amountCents, String currency) {}

    // ------------------------------------------------------------ extrato

    public record StatementView(List<TxView> transactions, long creditsCents,
                                long debitsCents) {}

    @GetMapping("/statement")
    @Operation(summary = "Extrato com filtros")
    public StatementView statement(
            CurrentUser me,
            @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to,
            @RequestParam(required = false) Boolean credits,
            @RequestParam(required = false) String search,
            @RequestParam(defaultValue = "100") int limit) {

        var txs = banking.statement(me.userId(), from, to, credits, search,
                Math.min(limit, 500));
        return new StatementView(txs.stream().map(TxView::of).toList(),
                banking.sumCredits(me.userId(), from, to).cents(),
                banking.sumDebits(me.userId(), from, to).cents());
    }

    @GetMapping("/statement/{transactionId}")
    @Operation(summary = "Comprovante de uma transação")
    public TxView transaction(CurrentUser me, @PathVariable UUID transactionId) {
        return banking.findTransaction(me.userId(), transactionId)
                .map(TxView::of)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Transação não encontrada."));
    }

    public record CategorySpendView(String category, long totalCents) {}

    @GetMapping("/statement/spending")
    @Operation(summary = "Gastos por categoria no período")
    public List<CategorySpendView> spending(
            CurrentUser me,
            @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to) {

        var start = from != null ? from : clock.today().withDayOfMonth(1);
        return banking.spendingByCategory(me.userId(), start, to != null ? to : clock.today())
                .stream()
                .map(c -> new CategorySpendView(c.category().name(), c.total().cents()))
                .toList();
    }

    /** Orçamento mensal padrão. Um passo natural seria torná-lo editável. */
    private static final Money MONTHLY_BUDGET = Money.of("4000.00");

    /**
     * Score de crédito derivado do histórico, em vez do 742 fixo do app.
     *
     * <p>Modelo simples e explicável: base que sobe com renda recebida,
     * organização (cofrinho/investimento) e empréstimo em dia, e cai com
     * parcela em atraso. Não é bureau de verdade — é aproximação honesta
     * para o ambiente de estudo.
     */
    private int creditScore(UUID userId, java.util.List<br.com.aurora.banking.domain.Goal> goals,
                            java.util.List<br.com.aurora.banking.domain.Loan> loans) {
        var last90 = clock.today().minusDays(90);
        int score = 600;

        // Renda: só salário conta, não empréstimo. Contar todo crédito faria
        // o cliente subir o próprio score tomando dinheiro emprestado.
        boolean hasIncome = banking.statement(userId, last90, clock.today(),
                        true, null, 200).stream()
                .anyMatch(t -> t.category() == br.com.aurora.banking.domain.TxCategory.salario);
        if (hasIncome) score += 80;

        // Organização financeira.
        if (!goals.isEmpty()) score += 60;

        // Histórico de crédito.
        for (var loan : loans) {
            if (loan.isSettled()) score += 40;
            else if (loan.nextDue().map(i -> i.isOverdue(clock.today())).orElse(false)) score -= 120;
            else score += 20;
        }
        return Math.max(300, Math.min(1000, score));
    }

    // ------------------------------------------------------ notificações

    @GetMapping("/notifications")
    @Operation(summary = "Central de mensagens")
    public List<BankingRepository.NotificationRow> notifications(CurrentUser me) {
        return banking.listNotifications(me.userId());
    }

    @PostMapping("/notifications/read")
    @Operation(summary = "Marca todas como lidas")
    public void markRead(CurrentUser me) {
        banking.markAllRead(me.userId());
    }

    // ---------------------------------------------------- consentimentos LGPD

    @GetMapping("/account/consents")
    @Operation(summary = "Meus consentimentos (LGPD)")
    public List<BankingRepository.ConsentRow> consents(CurrentUser me) {
        return banking.listConsents(me.userId());
    }

    public record ConsentRequest(String kind, boolean granted) {}

    @PutMapping("/account/consents")
    @Operation(summary = "Concede ou revoga um consentimento")
    public List<BankingRepository.ConsentRow> setConsent(CurrentUser me,
                                                         @RequestBody ConsentRequest r) {
        banking.setConsent(me.userId(), r.kind(), r.granted());
        return banking.listConsents(me.userId());
    }
}

package br.com.aurora.banking.adapters.rest;

import br.com.aurora.banking.application.*;
import br.com.aurora.banking.domain.TxCategory;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.rest.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static br.com.aurora.banking.adapters.rest.AccountController.TxView;

/** Os fluxos que movem dinheiro: Pix, cofrinho, investimento, cartão, crédito. */
@RestController
@RequestMapping("/v1")
@Tag(name = "Transações", description = "Pix, cofrinhos, investimentos, cartão e crédito")
public class TransactionController {

    private final PixService pix;
    private final GoalService goals;
    private final InvestmentService investments;
    private final CardService cards;
    private final LoanService loans;
    private final BankingRepository banking;

    public TransactionController(PixService pix, GoalService goals,
                                 InvestmentService investments, CardService cards,
                                 LoanService loans, BankingRepository banking) {
        this.pix = pix;
        this.goals = goals;
        this.investments = investments;
        this.cards = cards;
        this.loans = loans;
        this.banking = banking;
    }

    // ---------------------------------------------------------------- Pix

    public record PixSendRequest(@NotBlank String pixKey,
                                 @Positive long amountCents,
                                 String note) {}

    @PostMapping("/pix/send")
    @Operation(summary = "Envia Pix")
    public TxView sendPix(CurrentUser me, @Valid @RequestBody PixSendRequest r) {
        me.requireStrongAuth();
        return TxView.of(pix.send(new PixService.SendCommand(
                me.userId(), r.pixKey(), Money.ofCents(r.amountCents()), r.note())));
    }

    public record PixKeyRequest(@NotBlank String kind, String value) {}

    @GetMapping("/pix/keys")
    @Operation(summary = "Minhas chaves Pix")
    public List<BankingRepository.PixKeyRow> pixKeys(CurrentUser me) {
        return pix.keys(me.userId());
    }

    @PostMapping("/pix/keys")
    @Operation(summary = "Cadastra chave Pix")
    public BankingRepository.PixKeyRow createKey(CurrentUser me,
                                                 @Valid @RequestBody PixKeyRequest r) {
        return pix.createKey(me.userId(), r.kind(), r.value());
    }

    @DeleteMapping("/pix/keys/{keyId}")
    @Operation(summary = "Exclui chave Pix")
    public void deleteKey(CurrentUser me, @PathVariable UUID keyId) {
        pix.deleteKey(me.userId(), keyId);
    }

    @GetMapping("/pix/contacts")
    @Operation(summary = "Contatos recentes")
    public List<BankingRepository.ContactRow> contacts(CurrentUser me) {
        return banking.listContacts(me.userId(), 10);
    }

    public record ChargeRequest(Long amountCents, String description) {}

    @PostMapping("/pix/charges")
    @Operation(summary = "Cria uma cobrança Pix (o QR)")
    public BankingRepository.PixChargeRow createCharge(CurrentUser me,
                                                       @RequestBody ChargeRequest r) {
        var amount = r.amountCents() == null ? null : Money.ofCents(r.amountCents());
        return pix.createCharge(new PixService.ChargeCommand(me.userId(), amount, r.description()));
    }

    @GetMapping("/pix/charges")
    @Operation(summary = "Minhas cobranças Pix")
    public List<BankingRepository.PixChargeRow> charges(CurrentUser me) {
        return pix.charges(me.userId());
    }

    @PostMapping("/pix/{transactionId}/refund")
    @Operation(summary = "Devolve um Pix recebido (MED)")
    public TxView refund(CurrentUser me, @PathVariable UUID transactionId) {
        me.requireStrongAuth();
        return TxView.of(pix.refund(me.userId(), transactionId));
    }

    // ---------------------------------------------------------- cofrinhos

    public record GoalRequest(@NotBlank String name, @Positive long targetCents,
                              String symbol, LocalDate deadline) {}

    public record AmountRequest(@Positive long amountCents) {}

    @GetMapping("/goals")
    @Operation(summary = "Lista cofrinhos")
    public List<AccountController.GoalView> listGoals(CurrentUser me) {
        return goals.list(me.userId()).stream()
                .map(g -> new AccountController.GoalView(g.id(), g.name(),
                        g.saved().cents(), g.target().cents(), g.symbol(),
                        g.deadline(), g.progress()))
                .toList();
    }

    @PostMapping("/goals")
    @Operation(summary = "Cria cofrinho")
    public AccountController.GoalView createGoal(CurrentUser me,
                                                 @Valid @RequestBody GoalRequest r) {
        var g = goals.create(me.userId(), r.name(), Money.ofCents(r.targetCents()),
                r.symbol() == null ? "banknote.fill" : r.symbol(), r.deadline());
        return new AccountController.GoalView(g.id(), g.name(), g.saved().cents(),
                g.target().cents(), g.symbol(), g.deadline(), g.progress());
    }

    @PostMapping("/goals/{goalId}/deposit")
    @Operation(summary = "Guarda no cofrinho")
    public TxView deposit(CurrentUser me, @PathVariable UUID goalId,
                          @Valid @RequestBody AmountRequest r) {
        me.requireStrongAuth();
        return TxView.of(goals.deposit(me.userId(), goalId, Money.ofCents(r.amountCents())));
    }

    @PostMapping("/goals/{goalId}/withdraw")
    @Operation(summary = "Resgata do cofrinho")
    public TxView withdraw(CurrentUser me, @PathVariable UUID goalId,
                           @Valid @RequestBody AmountRequest r) {
        me.requireStrongAuth();
        return TxView.of(goals.withdraw(me.userId(), goalId, Money.ofCents(r.amountCents())));
    }

    @DeleteMapping("/goals/{goalId}")
    @Operation(summary = "Exclui cofrinho e devolve o guardado")
    public void deleteGoal(CurrentUser me, @PathVariable UUID goalId) {
        me.requireStrongAuth();
        goals.delete(me.userId(), goalId);
    }

    // ------------------------------------------------------ investimentos

    @GetMapping("/investments/products")
    @Operation(summary = "Produtos disponíveis")
    public List<BankingRepository.InvestmentProduct> products() {
        return investments.products();
    }

    @GetMapping("/investments/positions")
    @Operation(summary = "Minhas posições")
    public List<InvestmentService.Position> positions(CurrentUser me) {
        return investments.positions(me.userId());
    }

    @PostMapping("/investments/{productId}/invest")
    @Operation(summary = "Aplica")
    public TxView invest(CurrentUser me, @PathVariable String productId,
                         @Valid @RequestBody AmountRequest r) {
        me.requireStrongAuth();
        return TxView.of(investments.invest(me.userId(), productId,
                Money.ofCents(r.amountCents())));
    }

    @PostMapping("/investments/{productId}/apply-earnings")
    @Operation(summary = "Reaplica o rendimento da posição")
    public TxView applyEarnings(CurrentUser me, @PathVariable String productId) {
        me.requireStrongAuth();
        return TxView.of(investments.applyEarnings(me.userId(), productId));
    }

    @PostMapping("/investments/{productId}/redeem")
    @Operation(summary = "Resgata")
    public TxView redeem(CurrentUser me, @PathVariable String productId,
                         @Valid @RequestBody AmountRequest r) {
        me.requireStrongAuth();
        return TxView.of(investments.redeem(me.userId(), productId,
                Money.ofCents(r.amountCents())));
    }

    // ------------------------------------------------------------- cartão

    @GetMapping("/card")
    @Operation(summary = "Meu cartão principal e a fatura")
    public CardService.CardView card(CurrentUser me) {
        return cards.view(me.userId());
    }

    public record CardListItem(String id, String kind, String lastFour, String maskedNumber,
                               String expiry, boolean blocked) {}

    @GetMapping("/cards")
    @Operation(summary = "Lista todos os cartões (físico e virtuais)")
    public List<CardListItem> cardList(CurrentUser me) {
        return cards.list(me.userId()).stream()
                .map(c -> new CardListItem(c.id().toString(), c.kind(), c.lastFour(),
                        "•••• •••• •••• " + c.lastFour(), c.expiry(), c.blocked()))
                .toList();
    }

    public record VirtualCardView(String id, String number, String cvv,
                                  String expiry, String holderName) {}

    @PostMapping("/cards/virtual")
    @Operation(summary = "Cria um cartão virtual para compras online")
    public VirtualCardView createVirtual(CurrentUser me) {
        me.requireStrongAuth();
        var c = cards.createVirtual(me.userId());
        return new VirtualCardView(c.id().toString(), c.cardNumber(), c.cvv(),
                c.expiry(), c.holderName());
    }

    public record OnlinePurchaseRequest(@NotBlank String cardNumber, @NotBlank String cvv,
                                        @Positive long amountCents, @NotBlank String merchant,
                                        String category) {}

    @PostMapping("/cards/purchase")
    @Operation(summary = "Compra online informando número e CVV do cartão",
               description = "Valida cartão, CVV, bloqueio e limite; lança na fatura.")
    public TxView purchaseOnline(CurrentUser me, @Valid @RequestBody OnlinePurchaseRequest r) {
        me.requireStrongAuth();
        var category = r.category() == null ? TxCategory.outros : TxCategory.valueOf(r.category());
        return TxView.of(cards.authorizeByNumber(me.userId(), r.cardNumber(), r.cvv(),
                Money.ofCents(r.amountCents()), r.merchant(), category));
    }

    public record PurchaseRequest(@Positive long amountCents, @NotBlank String merchant,
                                  String category) {}

    @PostMapping("/card/purchase")
    @Operation(summary = "Registra compra no crédito",
               description = "Não toca a conta corrente: engorda a fatura.")
    public TxView purchase(CurrentUser me, @Valid @RequestBody PurchaseRequest r) {
        me.requireStrongAuth();
        var category = r.category() == null ? TxCategory.outros
                : TxCategory.valueOf(r.category());
        return TxView.of(cards.purchase(me.userId(), Money.ofCents(r.amountCents()),
                r.merchant(), category));
    }

    @PostMapping("/card/invoice/pay")
    @Operation(summary = "Paga a fatura com o saldo")
    public TxView payInvoice(CurrentUser me) {
        me.requireStrongAuth();
        return TxView.of(cards.payInvoice(me.userId()));
    }

    public record InstallInvoiceRequest(@Min(2) @Max(24) int months) {}

    public record InstallInvoiceResponse(java.util.UUID loanId) {}

    @PostMapping("/card/invoice/installment")
    @Operation(summary = "Parcela a fatura",
               description = "Quita a fatura atual e abre um empréstimo com as parcelas.")
    public InstallInvoiceResponse installInvoice(CurrentUser me,
                                                 @Valid @RequestBody InstallInvoiceRequest r) {
        me.requireStrongAuth();
        return new InstallInvoiceResponse(cards.installInvoice(me.userId(), r.months()));
    }

    public record CardSettingsRequest(Boolean blocked, Long creditLimitCents,
                                      Boolean contactless, Boolean onlinePurchases,
                                      Boolean international) {}

    @PatchMapping("/card/settings")
    @Operation(summary = "Ajustes do cartão")
    public CardService.CardView updateCard(CurrentUser me,
                                           @RequestBody CardSettingsRequest r) {
        me.requireStrongAuth();
        cards.updateSettings(me.userId(), r.blocked(),
                r.creditLimitCents() == null ? null : Money.ofCents(r.creditLimitCents()),
                r.contactless(), r.onlinePurchases(), r.international());
        return cards.view(me.userId());
    }

    // ------------------------------------------------------------ crédito

    @GetMapping("/credit/simulate")
    @Operation(summary = "Simula empréstimo")
    public LoanService.Simulation simulate(@RequestParam long amountCents,
                                           @RequestParam int months) {
        return loans.simulate(Money.ofCents(amountCents), months);
    }

    public record ContractRequest(@Positive long amountCents,
                                  @Min(1) @Max(48) int months) {}

    public record LoanView(UUID id, long principalCents, int installments,
                           long paidCount, long outstandingCents, String state,
                           List<InstallmentView> schedule) {}

    public record InstallmentView(UUID id, int number, long amountCents,
                                  LocalDate dueDate, boolean paid) {}

    @PostMapping("/credit/loans")
    @Operation(summary = "Contrata empréstimo",
               description = "Credita a conta e gera as parcelas devidas.")
    public LoanView contract(CurrentUser me, @Valid @RequestBody ContractRequest r) {
        me.requireStrongAuth();
        return toView(loans.contract(me.userId(), Money.ofCents(r.amountCents()), r.months()));
    }

    @GetMapping("/credit/loans")
    @Operation(summary = "Meus contratos")
    public List<LoanView> listLoans(CurrentUser me) {
        return loans.list(me.userId()).stream().map(TransactionController::toView).toList();
    }

    @PostMapping("/credit/loans/{loanId}/pay")
    @Operation(summary = "Paga a próxima parcela")
    public TxView payInstallment(CurrentUser me, @PathVariable UUID loanId) {
        me.requireStrongAuth();
        return TxView.of(loans.payNextInstallment(me.userId(), loanId));
    }

    private static LoanView toView(br.com.aurora.banking.domain.Loan loan) {
        return new LoanView(loan.id(), loan.principal().cents(), loan.installmentCount(),
                loan.paidCount(), loan.outstanding().cents(), loan.state().name(),
                loan.installments().stream()
                        .map(i -> new InstallmentView(i.id(), i.number(),
                                i.amount().cents(), i.dueDate(), i.isPaid()))
                        .toList());
    }
}

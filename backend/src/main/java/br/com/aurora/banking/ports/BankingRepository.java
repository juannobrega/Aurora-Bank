package br.com.aurora.banking.ports;

import br.com.aurora.banking.domain.*;
import br.com.aurora.shared.money.Money;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface BankingRepository {

    // Contas do usuário
    UUID checkingAccountOf(UUID userId);
    UUID settlementAccount();
    UUID revenueAccount();
    UUID fundingAccount();
    UUID expenseAccount();

    // Extrato
    void saveDetails(BankTransaction tx);
    List<BankTransaction> statement(UUID userId, LocalDate from, LocalDate to,
                                    Boolean onlyCredits, String search, int limit);
    Optional<BankTransaction> findTransaction(UUID userId, UUID transactionId);
    Money sumCredits(UUID userId, LocalDate from, LocalDate to);
    Money sumDebits(UUID userId, LocalDate from, LocalDate to);
    List<CategoryTotal> spendingByCategory(UUID userId, LocalDate from, LocalDate to);

    /**
     * Gasto do período: só categorias de despesa.
     *
     * <p>Diferente de {@code sumDebits}, que soma toda saída. Guardar no
     * cofrinho ou investir é saída de caixa, mas não é gasto — o dinheiro
     * continua seu, e contá-lo no orçamento mensal seria enganoso.
     */
    Money totalSpending(UUID userId, LocalDate from, LocalDate to);

    record CategoryTotal(TxCategory category, Money total) {}

    // Cofrinhos
    UUID createGoalAccount(UUID userId, String name);
    void saveGoal(Goal goal);
    List<Goal> listGoals(UUID userId);
    Optional<Goal> findGoal(UUID userId, UUID goalId);
    void archiveGoal(UUID goalId);

    // Investimentos
    List<InvestmentProduct> listProducts();
    Optional<InvestmentProduct> findProduct(String id);
    UUID ensureHoldingAccount(UUID userId, String productId);
    void addInvested(UUID userId, String productId, Money delta);
    List<HoldingRow> listHoldings(UUID userId);

    record InvestmentProduct(String id, String name, String rateLabel,
                             String liquidity, java.math.BigDecimal annualYield,
                             String accent) {}
    record HoldingRow(String productId, UUID accountId, Money invested) {}

    // Cartão
    Optional<CardRow> findCard(UUID userId);
    Optional<CardRow> findCardById(UUID userId, UUID cardId);
    Optional<CardRow> findCardByNumber(String cardNumber);
    List<CardRow> listCards(UUID userId);
    void createCard(UUID userId, UUID liabilityAccountId, String kind, String lastFour,
                    String expiry, String cardNumber, String cvv, String holderName);
    void updateCard(UUID cardId, boolean blocked, Money limit,
                    boolean contactless, boolean online, boolean international);

    record CardRow(UUID id, UUID userId, UUID liabilityAccountId, String kind,
                   String lastFour, String expiry, Money creditLimit, boolean blocked,
                   boolean contactless, boolean onlinePurchases, boolean international,
                   int invoiceDueDay, String cardNumber, String cvv, String holderName) {}

    // Empréstimos
    UUID createLoanAccount(UUID userId);
    void saveLoan(Loan loan);
    void decideLoan(UUID loanId, Loan.LoanState state, String decidedBy, String note);
    void markInstallmentPaid(UUID installmentId);
    List<Loan> listLoans(UUID userId);
    Optional<Loan> findLoan(UUID userId, UUID loanId);
    Optional<Loan> findLoanById(UUID loanId);
    List<PendingLoan> pendingLoans();

    record PendingLoan(UUID id, UUID userId, String userName, Money principal,
                       int installments, Money payment, java.time.Instant requestedAt) {}

    // Pix
    void savePixKey(UUID id, UUID userId, String kind, String value);
    void deletePixKey(UUID userId, UUID keyId);
    List<PixKeyRow> listPixKeys(UUID userId);
    Optional<PixKeyRow> findPixKeyByValue(String value);

    record PixKeyRow(UUID id, UUID userId, String kind, String value) {}

    void rememberContact(UUID userId, String name, String keyValue, String bank);
    List<ContactRow> listContacts(UUID userId, int limit);

    record ContactRow(UUID id, String name, String keyValue, String bank) {}

    // Rendimento automático
    java.util.List<UUID> checkingAccountsToAccrue();
    java.time.Instant lastAccrual(UUID accountId);
    void updateAccrual(UUID accountId, java.time.Instant at, Money yielded);

    // Pagamentos
    boolean isBoletoPaid(String digitableLine);
    void recordBoletoPayment(String digitableLine, UUID transactionId);

    // Atendimento
    String openTicket(UUID userId, String channel, String subject);
    List<TicketRow> listTickets(UUID userId);
    record TicketRow(UUID id, String channel, String subject, String status,
                     String protocol, java.time.Instant createdAt) {}

    // Cobrança Pix e devolução (MED)
    void savePixCharge(UUID id, UUID userId, String pixKey, Money amount,
                       String description, String txid);
    List<PixChargeRow> listPixCharges(UUID userId);
    record PixChargeRow(UUID id, String pixKey, Money amount, String description,
                        String txid, boolean paid, java.time.Instant createdAt) {}

    void markRefunded(UUID originalTxId, UUID refundTxId);

    // Consentimentos LGPD
    void setConsent(UUID userId, String kind, boolean granted);
    List<ConsentRow> listConsents(UUID userId);
    record ConsentRow(String kind, boolean granted, java.time.Instant createdAt) {}

    // Notificações
    void notify(UUID userId, String kind, String title, String message);
    List<NotificationRow> listNotifications(UUID userId);
    void markAllRead(UUID userId);

    record NotificationRow(UUID id, String kind, String title, String message,
                           boolean read, java.time.Instant createdAt) {}
}

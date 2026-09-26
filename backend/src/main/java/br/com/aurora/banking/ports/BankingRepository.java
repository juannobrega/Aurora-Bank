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
    void createCard(UUID userId, UUID liabilityAccountId, String lastFour, String expiry);
    void updateCard(UUID cardId, boolean blocked, Money limit,
                    boolean contactless, boolean online, boolean international);

    record CardRow(UUID id, UUID userId, UUID liabilityAccountId, String kind,
                   String lastFour, String expiry, Money creditLimit, boolean blocked,
                   boolean contactless, boolean onlinePurchases, boolean international,
                   int invoiceDueDay) {}

    // Empréstimos
    UUID createLoanAccount(UUID userId);
    void saveLoan(Loan loan);
    void markInstallmentPaid(UUID installmentId);
    List<Loan> listLoans(UUID userId);
    Optional<Loan> findLoan(UUID userId, UUID loanId);

    // Pix
    void savePixKey(UUID id, UUID userId, String kind, String value);
    void deletePixKey(UUID userId, UUID keyId);
    List<PixKeyRow> listPixKeys(UUID userId);
    Optional<PixKeyRow> findPixKeyByValue(String value);

    record PixKeyRow(UUID id, UUID userId, String kind, String value) {}

    void rememberContact(UUID userId, String name, String keyValue, String bank);
    List<ContactRow> listContacts(UUID userId, int limit);

    record ContactRow(UUID id, String name, String keyValue, String bank) {}

    // Notificações
    void notify(UUID userId, String kind, String title, String message);
    List<NotificationRow> listNotifications(UUID userId);
    void markAllRead(UUID userId);

    record NotificationRow(UUID id, String kind, String title, String message,
                           boolean read, java.time.Instant createdAt) {}
}

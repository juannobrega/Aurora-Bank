package br.com.aurora.banking.adapters.persistence;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.ledger.domain.Account;
import br.com.aurora.ledger.domain.AccountType;
import br.com.aurora.ledger.domain.LedgerRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.Date;
import java.time.LocalDate;
import java.util.*;

@Repository
public class JdbcBankingRepository implements BankingRepository {

    private final NamedParameterJdbcTemplate jdbc;
    private final LedgerRepository ledger;

    /** Contas internas do banco, criadas sob demanda e reaproveitadas. */
    private static final UUID SYSTEM_TENANT =
            UUID.fromString("00000000-0000-0000-0000-00000000a111");

    public JdbcBankingRepository(NamedParameterJdbcTemplate jdbc, LedgerRepository ledger) {
        this.jdbc = jdbc;
        this.ledger = ledger;
    }

    // ------------------------------------------------------------- contas

    @Override
    public UUID checkingAccountOf(UUID userId) {
        return jdbc.query("""
            SELECT id FROM accounts
             WHERE owner_id = :user AND type = 'CHECKING' AND closed_at IS NULL
             ORDER BY created_at
             LIMIT 1
            """, Map.of("user", userId), (rs, n) -> rs.getObject("id", UUID.class))
            .stream().findFirst()
            .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA));
    }

    @Override public UUID settlementAccount() { return systemAccount(AccountType.SETTLEMENT, "Liquidação"); }
    @Override public UUID revenueAccount()    { return systemAccount(AccountType.REVENUE, "Receita"); }
    @Override public UUID fundingAccount()    { return systemAccount(AccountType.FUNDING, "Funding"); }
    @Override public UUID expenseAccount()    { return systemAccount(AccountType.EXPENSE, "Despesa de terceiros"); }

    /** Conta interna do banco: uma por tipo, criada na primeira vez. */
    private synchronized UUID systemAccount(AccountType type, String name) {
        var found = jdbc.query("""
            SELECT id FROM accounts
             WHERE owner_id IS NULL AND type = CAST(:type AS account_type)
             LIMIT 1
            """, Map.of("type", type.name()),
            (rs, n) -> rs.getObject("id", UUID.class)).stream().findFirst();

        if (found.isPresent()) return found.get();

        var account = new Account(UUID.randomUUID(), SYSTEM_TENANT, null, type,
                name, Money.ZERO, true);
        ledger.saveAccount(account);
        return account.id();
    }

    // ------------------------------------------------------------ extrato

    @Override
    public void saveDetails(BankTransaction tx) {
        jdbc.update("""
            INSERT INTO tx_details (transaction_id, user_id, title, counterparty,
                                    category, method, is_credit, amount, note)
            VALUES (:id, :user, :title, :counterparty,
                    CAST(:category AS tx_category), CAST(:method AS tx_method),
                    :credit, :amount, :note)
            """,
            new MapSqlParameterSource()
                .addValue("id", tx.id())
                .addValue("user", tx.userId())
                .addValue("title", tx.title())
                .addValue("counterparty", tx.counterparty())
                .addValue("category", tx.category().name())
                .addValue("method", tx.method().name())
                .addValue("credit", tx.isCredit())
                .addValue("amount", tx.amount().amount())
                .addValue("note", tx.note()));
    }

    @Override
    public List<BankTransaction> statement(UUID userId, LocalDate from, LocalDate to,
                                           Boolean onlyCredits, String search, int limit) {
        var params = new MapSqlParameterSource()
                .addValue("user", userId)
                .addValue("from", from == null ? null : Date.valueOf(from))
                .addValue("to", to == null ? null : Date.valueOf(to))
                .addValue("credits", onlyCredits)
                .addValue("search", search == null || search.isBlank() ? null : "%" + search + "%")
                .addValue("limit", limit);

        return jdbc.query("""
            SELECT d.*, t.occurred_at, t.auth_code
              FROM tx_details d
              JOIN transactions t ON t.id = d.transaction_id
             WHERE d.user_id = :user
               AND (:from::date IS NULL OR t.occurred_at >= :from::date)
               AND (:to::date   IS NULL OR t.occurred_at <  (:to::date + 1))
               AND (:credits::boolean IS NULL OR d.is_credit = :credits::boolean)
               AND (:search::text IS NULL
                    OR d.title ILIKE :search OR d.counterparty ILIKE :search)
             ORDER BY t.occurred_at DESC
             LIMIT :limit
            """, params, TX_MAPPER);
    }

    @Override
    public Optional<BankTransaction> findTransaction(UUID userId, UUID transactionId) {
        return jdbc.query("""
            SELECT d.*, t.occurred_at, t.auth_code
              FROM tx_details d JOIN transactions t ON t.id = d.transaction_id
             WHERE d.user_id = :user AND d.transaction_id = :id
            """, Map.of("user", userId, "id", transactionId), TX_MAPPER)
            .stream().findFirst();
    }

    @Override
    public Money sumCredits(UUID userId, LocalDate from, LocalDate to) {
        return sum(userId, from, to, true);
    }

    @Override
    public Money sumDebits(UUID userId, LocalDate from, LocalDate to) {
        return sum(userId, from, to, false);
    }

    private Money sum(UUID userId, LocalDate from, LocalDate to, boolean credits) {
        var total = jdbc.queryForObject("""
            SELECT COALESCE(SUM(d.amount), 0)
              FROM tx_details d JOIN transactions t ON t.id = d.transaction_id
             WHERE d.user_id = :user AND d.is_credit = :credits
               AND (:from::date IS NULL OR t.occurred_at >= :from::date)
               AND (:to::date   IS NULL OR t.occurred_at <  (:to::date + 1))
            """,
            new MapSqlParameterSource()
                .addValue("user", userId).addValue("credits", credits)
                .addValue("from", from == null ? null : Date.valueOf(from))
                .addValue("to", to == null ? null : Date.valueOf(to)),
            BigDecimal.class);
        return new Money(total == null ? BigDecimal.ZERO : total);
    }

    @Override
    public Money totalSpending(UUID userId, LocalDate from, LocalDate to) {
        return spendingByCategory(userId, from, to).stream()
                .map(CategoryTotal::total)
                .reduce(Money.ZERO, Money::plus);
    }

    /**
     * Gastos por categoria. Só categorias de despesa entram — a regra
     * {@code isSpending} vive no enum e é aplicada aqui.
     */
    @Override
    public List<CategoryTotal> spendingByCategory(UUID userId, LocalDate from, LocalDate to) {
        var excluded = Arrays.stream(TxCategory.values())
                .filter(c -> !c.isSpending()).map(Enum::name).toList();

        return jdbc.query("""
            SELECT d.category, SUM(d.amount) AS total
              FROM tx_details d JOIN transactions t ON t.id = d.transaction_id
             WHERE d.user_id = :user AND d.is_credit = false
               AND d.category::text <> ALL (:excluded)
               AND (:from::date IS NULL OR t.occurred_at >= :from::date)
               AND (:to::date   IS NULL OR t.occurred_at <  (:to::date + 1))
             GROUP BY d.category
             ORDER BY total DESC
            """,
            new MapSqlParameterSource()
                .addValue("user", userId)
                .addValue("excluded", excluded.toArray(String[]::new))
                .addValue("from", from == null ? null : Date.valueOf(from))
                .addValue("to", to == null ? null : Date.valueOf(to)),
            (rs, n) -> new CategoryTotal(
                    TxCategory.valueOf(rs.getString("category")),
                    new Money(rs.getBigDecimal("total"))));
    }

    // ---------------------------------------------------------- cofrinhos

    @Override
    public UUID createGoalAccount(UUID userId, String name) {
        var account = new Account(UUID.randomUUID(), userId, userId,
                AccountType.GOAL, "Cofrinho: " + name, Money.ZERO, false);
        ledger.saveAccount(account);
        return account.id();
    }

    @Override
    public void saveGoal(Goal g) {
        jdbc.update("""
            INSERT INTO goals (id, user_id, account_id, name, target, symbol, deadline)
            VALUES (:id, :user, :account, :name, :target, :symbol, :deadline)
            """,
            new MapSqlParameterSource()
                .addValue("id", g.id()).addValue("user", g.userId())
                .addValue("account", g.accountId()).addValue("name", g.name())
                .addValue("target", g.target().amount()).addValue("symbol", g.symbol())
                .addValue("deadline", g.deadline() == null ? null : Date.valueOf(g.deadline())));
    }

    @Override
    public List<Goal> listGoals(UUID userId) {
        return jdbc.query("""
            SELECT * FROM goals WHERE user_id = :user AND archived_at IS NULL
             ORDER BY created_at
            """, Map.of("user", userId), goalMapper());
    }

    @Override
    public Optional<Goal> findGoal(UUID userId, UUID goalId) {
        return jdbc.query("""
            SELECT * FROM goals
             WHERE user_id = :user AND id = :id AND archived_at IS NULL
            """, Map.of("user", userId, "id", goalId), goalMapper())
            .stream().findFirst();
    }

    @Override
    public void archiveGoal(UUID goalId) {
        jdbc.update("UPDATE goals SET archived_at = now() WHERE id = :id",
                Map.of("id", goalId));
    }

    /** O valor guardado é o saldo da conta, lido do razão. */
    private RowMapper<Goal> goalMapper() {
        return (rs, n) -> {
            var accountId = rs.getObject("account_id", UUID.class);
            var deadline = rs.getDate("deadline");
            return new Goal(
                    rs.getObject("id", UUID.class),
                    rs.getObject("user_id", UUID.class),
                    accountId,
                    rs.getString("name"),
                    new Money(rs.getBigDecimal("target")),
                    ledger.balanceOf(accountId),
                    rs.getString("symbol"),
                    deadline == null ? null : deadline.toLocalDate());
        };
    }

    // ------------------------------------------------------ investimentos

    @Override
    public List<InvestmentProduct> listProducts() {
        return jdbc.query("SELECT * FROM investment_products ORDER BY id", PRODUCT_MAPPER);
    }

    @Override
    public Optional<InvestmentProduct> findProduct(String id) {
        return jdbc.query("SELECT * FROM investment_products WHERE id = :id",
                Map.of("id", id), PRODUCT_MAPPER).stream().findFirst();
    }

    @Override
    public synchronized UUID ensureHoldingAccount(UUID userId, String productId) {
        var existing = jdbc.query("""
            SELECT account_id FROM holdings WHERE user_id = :user AND product_id = :p
            """, Map.of("user", userId, "p", productId),
            (rs, n) -> rs.getObject("account_id", UUID.class)).stream().findFirst();

        if (existing.isPresent()) return existing.get();

        var account = new Account(UUID.randomUUID(), userId, userId,
                AccountType.INVESTMENT, "Posição: " + productId, Money.ZERO, false);
        ledger.saveAccount(account);

        jdbc.update("""
            INSERT INTO holdings (id, user_id, product_id, account_id, invested)
            VALUES (:id, :user, :p, :account, 0)
            """,
            Map.of("id", UUID.randomUUID(), "user", userId,
                   "p", productId, "account", account.id()));
        return account.id();
    }

    @Override
    public void addInvested(UUID userId, String productId, Money delta) {
        jdbc.update("""
            UPDATE holdings SET invested = GREATEST(0, invested + :delta)
             WHERE user_id = :user AND product_id = :p
            """,
            Map.of("user", userId, "p", productId, "delta", delta.amount()));
    }

    @Override
    public List<HoldingRow> listHoldings(UUID userId) {
        return jdbc.query("""
            SELECT product_id, account_id, invested FROM holdings
             WHERE user_id = :user ORDER BY product_id
            """, Map.of("user", userId),
            (rs, n) -> new HoldingRow(rs.getString("product_id"),
                    rs.getObject("account_id", UUID.class),
                    new Money(rs.getBigDecimal("invested"))));
    }

    // ------------------------------------------------------------- cartão

    @Override
    public Optional<CardRow> findCard(UUID userId) {
        return jdbc.query("SELECT * FROM cards WHERE user_id = :user LIMIT 1",
                Map.of("user", userId), CARD_MAPPER).stream().findFirst();
    }

    @Override
    public void createCard(UUID userId, UUID liabilityAccountId, String lastFour, String expiry) {
        jdbc.update("""
            INSERT INTO cards (id, user_id, liability_account_id, last_four, expiry)
            VALUES (:id, :user, :account, :last4, :expiry)
            """,
            Map.of("id", UUID.randomUUID(), "user", userId,
                   "account", liabilityAccountId, "last4", lastFour, "expiry", expiry));
    }

    @Override
    public void updateCard(UUID cardId, boolean blocked, Money limit,
                           boolean contactless, boolean online, boolean international) {
        jdbc.update("""
            UPDATE cards SET blocked = :blocked, credit_limit = :limit,
                   contactless = :contactless, online_purchases = :online,
                   international = :intl
             WHERE id = :id
            """,
            new MapSqlParameterSource()
                .addValue("id", cardId).addValue("blocked", blocked)
                .addValue("limit", limit.amount()).addValue("contactless", contactless)
                .addValue("online", online).addValue("intl", international));
    }

    // -------------------------------------------------------- empréstimos

    @Override
    public UUID createLoanAccount(UUID userId) {
        var account = new Account(UUID.randomUUID(), userId, userId,
                AccountType.LOAN_LIABILITY, "Empréstimo", Money.ZERO, true);
        ledger.saveAccount(account);
        return account.id();
    }

    @Override
    public void saveLoan(Loan loan) {
        jdbc.update("""
            INSERT INTO loans (id, user_id, liability_account_id, principal,
                               monthly_rate, installments)
            VALUES (:id, :user, :account, :principal, :rate, :count)
            """,
            new MapSqlParameterSource()
                .addValue("id", loan.id()).addValue("user", loan.userId())
                .addValue("account", loan.liabilityAccountId())
                .addValue("principal", loan.principal().amount())
                .addValue("rate", loan.monthlyRate())
                .addValue("count", loan.installmentCount()));

        var batch = loan.installments().stream()
                .map(i -> new MapSqlParameterSource()
                        .addValue("id", i.id()).addValue("loan", loan.id())
                        .addValue("number", i.number())
                        .addValue("amount", i.amount().amount())
                        .addValue("due", Date.valueOf(i.dueDate())))
                .toArray(MapSqlParameterSource[]::new);

        jdbc.batchUpdate("""
            INSERT INTO installments (id, loan_id, number, amount, due_date)
            VALUES (:id, :loan, :number, :amount, :due)
            """, batch);
    }

    @Override
    public void markInstallmentPaid(UUID installmentId) {
        jdbc.update("UPDATE installments SET paid_at = now() WHERE id = :id",
                Map.of("id", installmentId));
    }

    @Override
    public List<Loan> listLoans(UUID userId) {
        return jdbc.query("SELECT * FROM loans WHERE user_id = :user ORDER BY contracted_at DESC",
                Map.of("user", userId), loanMapper());
    }

    @Override
    public Optional<Loan> findLoan(UUID userId, UUID loanId) {
        return jdbc.query("SELECT * FROM loans WHERE user_id = :user AND id = :id",
                Map.of("user", userId, "id", loanId), loanMapper())
                .stream().findFirst();
    }

    private RowMapper<Loan> loanMapper() {
        return (rs, n) -> {
            var loanId = rs.getObject("id", UUID.class);
            var installments = jdbc.query("""
                SELECT * FROM installments WHERE loan_id = :loan ORDER BY number
                """, Map.of("loan", loanId),
                (r, i) -> new Installment(
                        r.getObject("id", UUID.class), loanId,
                        r.getInt("number"), new Money(r.getBigDecimal("amount")),
                        r.getDate("due_date").toLocalDate(),
                        r.getTimestamp("paid_at") == null ? null
                                : r.getTimestamp("paid_at").toInstant()));

            return new Loan(loanId, rs.getObject("user_id", UUID.class),
                    rs.getObject("liability_account_id", UUID.class),
                    new Money(rs.getBigDecimal("principal")),
                    rs.getBigDecimal("monthly_rate"),
                    rs.getInt("installments"), installments,
                    rs.getTimestamp("contracted_at").toInstant());
        };
    }

    // ---------------------------------------------------------------- Pix

    @Override
    public void savePixKey(UUID id, UUID userId, String kind, String value) {
        jdbc.update("""
            INSERT INTO pix_keys (id, user_id, kind, value)
            VALUES (:id, :user, CAST(:kind AS pix_key_kind), :value)
            """, Map.of("id", id, "user", userId, "kind", kind, "value", value));
    }

    @Override
    public void deletePixKey(UUID userId, UUID keyId) {
        jdbc.update("DELETE FROM pix_keys WHERE user_id = :user AND id = :id",
                Map.of("user", userId, "id", keyId));
    }

    @Override
    public List<PixKeyRow> listPixKeys(UUID userId) {
        return jdbc.query("SELECT * FROM pix_keys WHERE user_id = :user ORDER BY created_at",
                Map.of("user", userId), PIX_KEY_MAPPER);
    }

    @Override
    public Optional<PixKeyRow> findPixKeyByValue(String value) {
        return jdbc.query("SELECT * FROM pix_keys WHERE value = :value",
                Map.of("value", value), PIX_KEY_MAPPER).stream().findFirst();
    }

    @Override
    public void rememberContact(UUID userId, String name, String keyValue, String bank) {
        jdbc.update("""
            INSERT INTO contacts (id, user_id, name, key_value, bank)
            VALUES (:id, :user, :name, :key, :bank)
            ON CONFLICT (user_id, key_value) DO UPDATE
               SET last_used_at = now(), name = EXCLUDED.name
            """,
            Map.of("id", UUID.randomUUID(), "user", userId,
                   "name", name, "key", keyValue, "bank", bank == null ? "" : bank));
    }

    @Override
    public List<ContactRow> listContacts(UUID userId, int limit) {
        return jdbc.query("""
            SELECT * FROM contacts WHERE user_id = :user
             ORDER BY last_used_at DESC LIMIT :limit
            """,
            new MapSqlParameterSource().addValue("user", userId).addValue("limit", limit),
            (rs, n) -> new ContactRow(rs.getObject("id", UUID.class),
                    rs.getString("name"), rs.getString("key_value"), rs.getString("bank")));
    }

    // --------------------------------------------------------- pagamentos

    @Override
    public boolean isBoletoPaid(String digitableLine) {
        return Boolean.TRUE.equals(jdbc.queryForObject("""
            SELECT EXISTS(SELECT 1 FROM boleto_payments WHERE digitable_line = :line)
            """, Map.of("line", digitableLine), Boolean.class));
    }

    @Override
    public void recordBoletoPayment(String digitableLine, UUID transactionId) {
        jdbc.update("""
            INSERT INTO boleto_payments (digitable_line, transaction_id)
            VALUES (:line, :tx)
            """, Map.of("line", digitableLine, "tx", transactionId));
    }

    // ---------------------------------------------------------- atendimento

    @Override
    public String openTicket(UUID userId, String channel, String subject) {
        // Protocolo curto e legível, do tipo que o cliente anota.
        String protocol = "AUR" + java.time.Year.now().getValue()
                + String.format("%06d", Math.abs(UUID.randomUUID().hashCode()) % 1_000_000);
        jdbc.update("""
            INSERT INTO support_tickets (id, user_id, channel, subject, protocol)
            VALUES (:id, :user, CAST(:ch AS ticket_channel), :subject, :proto)
            """,
            Map.of("id", UUID.randomUUID(), "user", userId, "ch", channel,
                   "subject", subject, "proto", protocol));
        return protocol;
    }

    @Override
    public List<TicketRow> listTickets(UUID userId) {
        return jdbc.query("""
            SELECT * FROM support_tickets WHERE user_id = :user ORDER BY created_at DESC
            """, Map.of("user", userId),
            (rs, n) -> new TicketRow(rs.getObject("id", UUID.class),
                    rs.getString("channel"), rs.getString("subject"),
                    rs.getString("status"), rs.getString("protocol"),
                    rs.getTimestamp("created_at").toInstant()));
    }

    // ----------------------------------------------------- cobrança Pix / MED

    @Override
    public void savePixCharge(UUID id, UUID userId, String pixKey, Money amount,
                              String description, String txid) {
        jdbc.update("""
            INSERT INTO pix_charges (id, user_id, pix_key, amount, description, txid)
            VALUES (:id, :user, :key, :amount, :desc, :txid)
            """,
            new MapSqlParameterSource()
                .addValue("id", id).addValue("user", userId).addValue("key", pixKey)
                .addValue("amount", amount == null ? null : amount.amount())
                .addValue("desc", description).addValue("txid", txid));
    }

    @Override
    public List<PixChargeRow> listPixCharges(UUID userId) {
        return jdbc.query("""
            SELECT * FROM pix_charges WHERE user_id = :user ORDER BY created_at DESC LIMIT 50
            """, Map.of("user", userId),
            (rs, n) -> new PixChargeRow(rs.getObject("id", UUID.class),
                    rs.getString("pix_key"),
                    rs.getBigDecimal("amount") == null ? null : new Money(rs.getBigDecimal("amount")),
                    rs.getString("description"), rs.getString("txid"),
                    rs.getTimestamp("paid_at") != null,
                    rs.getTimestamp("created_at").toInstant()));
    }

    @Override
    public void markRefunded(UUID originalTxId, UUID refundTxId) {
        jdbc.update("UPDATE tx_details SET refunded_tx_id = :refund WHERE transaction_id = :orig",
                Map.of("refund", refundTxId, "orig", originalTxId));
    }

    // ------------------------------------------------------- consentimentos

    @Override
    public void setConsent(UUID userId, String kind, boolean granted) {
        jdbc.update("""
            INSERT INTO consents (id, user_id, kind, granted)
            VALUES (:id, :user, :kind, :granted)
            """,
            Map.of("id", UUID.randomUUID(), "user", userId, "kind", kind, "granted", granted));
    }

    @Override
    public List<ConsentRow> listConsents(UUID userId) {
        // O estado atual de cada tipo é o registro mais recente dele.
        return jdbc.query("""
            SELECT DISTINCT ON (kind) kind, granted, created_at
              FROM consents WHERE user_id = :user
             ORDER BY kind, created_at DESC
            """, Map.of("user", userId),
            (rs, n) -> new ConsentRow(rs.getString("kind"), rs.getBoolean("granted"),
                    rs.getTimestamp("created_at").toInstant()));
    }

    // -------------------------------------------------------- notificações

    @Override
    public void notify(UUID userId, String kind, String title, String message) {
        jdbc.update("""
            INSERT INTO notifications (id, user_id, kind, title, message)
            VALUES (:id, :user, CAST(:kind AS notification_kind), :title, :message)
            """,
            Map.of("id", UUID.randomUUID(), "user", userId,
                   "kind", kind, "title", title, "message", message));
    }

    @Override
    public List<NotificationRow> listNotifications(UUID userId) {
        return jdbc.query("""
            SELECT * FROM notifications WHERE user_id = :user
             ORDER BY created_at DESC LIMIT 50
            """, Map.of("user", userId),
            (rs, n) -> new NotificationRow(rs.getObject("id", UUID.class),
                    rs.getString("kind"), rs.getString("title"), rs.getString("message"),
                    rs.getTimestamp("read_at") != null,
                    rs.getTimestamp("created_at").toInstant()));
    }

    @Override
    public void markAllRead(UUID userId) {
        jdbc.update("""
            UPDATE notifications SET read_at = now()
             WHERE user_id = :user AND read_at IS NULL
            """, Map.of("user", userId));
    }

    // ------------------------------------------------------------ mappers

    private static final RowMapper<BankTransaction> TX_MAPPER = (rs, n) -> new BankTransaction(
            rs.getObject("transaction_id", UUID.class),
            rs.getObject("user_id", UUID.class),
            rs.getString("title"), rs.getString("counterparty"),
            TxCategory.valueOf(rs.getString("category")),
            TxMethod.valueOf(rs.getString("method")),
            rs.getBoolean("is_credit"),
            new Money(rs.getBigDecimal("amount")),
            rs.getString("auth_code"),
            rs.getTimestamp("occurred_at").toInstant(),
            rs.getString("note"));

    private static final RowMapper<InvestmentProduct> PRODUCT_MAPPER = (rs, n) ->
            new InvestmentProduct(rs.getString("id"), rs.getString("name"),
                    rs.getString("rate_label"), rs.getString("liquidity"),
                    rs.getBigDecimal("annual_yield"), rs.getString("accent"));

    private static final RowMapper<CardRow> CARD_MAPPER = (rs, n) -> new CardRow(
            rs.getObject("id", UUID.class), rs.getObject("user_id", UUID.class),
            rs.getObject("liability_account_id", UUID.class), rs.getString("kind"),
            rs.getString("last_four"), rs.getString("expiry"),
            new Money(rs.getBigDecimal("credit_limit")), rs.getBoolean("blocked"),
            rs.getBoolean("contactless"), rs.getBoolean("online_purchases"),
            rs.getBoolean("international"), rs.getInt("invoice_due_day"));

    private static final RowMapper<PixKeyRow> PIX_KEY_MAPPER = (rs, n) -> new PixKeyRow(
            rs.getObject("id", UUID.class), rs.getObject("user_id", UUID.class),
            rs.getString("kind"), rs.getString("value"));
}

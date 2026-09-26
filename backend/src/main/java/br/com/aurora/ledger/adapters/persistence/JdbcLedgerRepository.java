package br.com.aurora.ledger.adapters.persistence;

import br.com.aurora.ledger.domain.*;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Persistência do razão em SQL direto.
 *
 * <p>JPA seria pior aqui: as pernas entram em um único {@code INSERT} em
 * lote e o saldo é uma agregação. Mapear isso por entidades adicionaria
 * indireção sem ganho. O resto do sistema pode usar JPA à vontade.
 */
@Repository
public class JdbcLedgerRepository implements LedgerRepository {

    private final NamedParameterJdbcTemplate jdbc;
    private final AuroraClock clock;

    public JdbcLedgerRepository(NamedParameterJdbcTemplate jdbc, AuroraClock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Override
    public void saveAccount(Account account) {
        jdbc.update("""
            INSERT INTO accounts (id, tenant_id, owner_id, type, name,
                                  opening_balance, allows_negative)
            VALUES (:id, :tenant, :owner, CAST(:type AS account_type), :name,
                    :opening, :negative)
            """,
            new MapSqlParameterSource()
                .addValue("id", account.id())
                .addValue("tenant", account.tenantId())
                .addValue("owner", account.ownerId())
                .addValue("type", account.type().name())
                .addValue("name", account.name())
                .addValue("opening", account.openingBalance().amount())
                .addValue("negative", account.allowsNegative()));
    }

    @Override
    public Optional<Account> findAccount(UUID accountId) {
        var rows = jdbc.query("""
            SELECT id, tenant_id, owner_id, type, name, opening_balance, allows_negative
              FROM accounts WHERE id = :id
            """,
            Map.of("id", accountId), ACCOUNT_MAPPER);
        return rows.stream().findFirst();
    }

    /**
     * Grava transação e pernas na mesma transação SQL. A constraint
     * {@code DEFERRABLE} valida a soma zero no COMMIT — se falhar aqui,
     * é bug de programação, não entrada inválida do usuário.
     */
    @Override
    @Transactional
    public void append(LedgerTransaction tx) {
        jdbc.update("""
            INSERT INTO transactions (id, tenant_id, kind, description, state,
                                      auth_code, occurred_at, settled_at)
            VALUES (:id, :tenant, :kind, :description,
                    CAST('SETTLED' AS transaction_state),
                    :authCode, :occurredAt, :occurredAt)
            """,
            new MapSqlParameterSource()
                .addValue("id", tx.id())
                .addValue("tenant", tx.tenantId())
                .addValue("kind", tx.kind())
                .addValue("description", tx.description())
                .addValue("authCode", newAuthCode())
                .addValue("occurredAt", java.sql.Timestamp.from(tx.occurredAt())));

        LocalDate effective = LocalDate.ofInstant(tx.occurredAt(), AuroraClock.BRAZIL);
        SqlParameterSource[] batch = tx.entries().stream()
            .map(e -> new MapSqlParameterSource()
                .addValue("id", UUID.randomUUID())
                .addValue("transactionId", tx.id())
                .addValue("accountId", e.accountId())
                .addValue("direction", e.direction().name())
                .addValue("amount", e.amount().amount())
                .addValue("postedAt", java.sql.Timestamp.from(tx.occurredAt()))
                .addValue("effectiveDate", java.sql.Date.valueOf(effective)))
            .toArray(SqlParameterSource[]::new);

        jdbc.batchUpdate("""
            INSERT INTO ledger_entries (id, transaction_id, account_id, direction,
                                        amount, posted_at, effective_date)
            VALUES (:id, :transactionId, :accountId,
                    CAST(:direction AS entry_direction),
                    :amount, :postedAt, :effectiveDate)
            """, batch);
    }

    @Override
    public Money balanceOf(UUID accountId) {
        var balance = jdbc.queryForObject("""
            SELECT a.opening_balance + COALESCE(SUM(
                       CASE WHEN e.direction = 'CREDIT' THEN e.amount ELSE -e.amount END
                   ), 0)
              FROM accounts a
              LEFT JOIN ledger_entries e ON e.account_id = a.id
             WHERE a.id = :id
             GROUP BY a.opening_balance
            """,
            Map.of("id", accountId), java.math.BigDecimal.class);

        if (balance == null) {
            throw new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA);
        }
        return new Money(balance);
    }

    @Override
    public List<PostedEntry> statement(UUID accountId, int limit) {
        return jdbc.query("""
            SELECT e.id, e.transaction_id, e.account_id, e.direction, e.amount,
                   e.sequence, e.posted_at, e.effective_date, t.kind, t.description
              FROM ledger_entries e
              JOIN transactions t ON t.id = e.transaction_id
             WHERE e.account_id = :id
             ORDER BY e.sequence DESC
             LIMIT :limit
            """,
            new MapSqlParameterSource()
                .addValue("id", accountId)
                .addValue("limit", limit, Types.INTEGER),
            ENTRY_MAPPER);
    }

    /** Código de autenticação no formato E2E do Pix. */
    private static String newAuthCode() {
        return "E" + UUID.randomUUID().toString().replace("-", "").toUpperCase().substring(0, 31);
    }

    private static final RowMapper<Account> ACCOUNT_MAPPER = (rs, n) -> new Account(
            rs.getObject("id", UUID.class),
            rs.getObject("tenant_id", UUID.class),
            rs.getObject("owner_id", UUID.class),
            AccountType.valueOf(rs.getString("type")),
            rs.getString("name"),
            new Money(rs.getBigDecimal("opening_balance")),
            rs.getBoolean("allows_negative"));

    private static final RowMapper<PostedEntry> ENTRY_MAPPER = (rs, n) -> new PostedEntry(
            rs.getObject("id", UUID.class),
            rs.getObject("transaction_id", UUID.class),
            rs.getObject("account_id", UUID.class),
            Direction.valueOf(rs.getString("direction")),
            new Money(rs.getBigDecimal("amount")),
            rs.getLong("sequence"),
            rs.getTimestamp("posted_at").toInstant(),
            rs.getDate("effective_date").toLocalDate(),
            rs.getString("kind"),
            rs.getString("description"));
}

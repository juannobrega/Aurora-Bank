package br.com.aurora.admin;

import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Consultas de gestão: visão agregada que os endpoints de cliente não dão.
 *
 * <p>Só leitura. Um painel administrativo observa o sistema; não movimenta
 * dinheiro — para isso existem os fluxos do próprio cliente.
 */
@Repository
public class AdminRepository {

    private final NamedParameterJdbcTemplate jdbc;

    public AdminRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record Metrics(long users, long activeUsers, long transactions,
                          long openLoans, BigDecimal totalDeposits,
                          BigDecimal totalInvested, BigDecimal ledgerBalance) {}

    public Metrics metrics() {
        return jdbc.queryForObject("""
            SELECT
              (SELECT count(*) FROM users) AS users,
              (SELECT count(*) FROM users WHERE status = 'ACTIVE') AS active_users,
              (SELECT count(*) FROM transactions) AS transactions,
              (SELECT count(*) FROM loans WHERE state = 'ACTIVE') AS open_loans,
              (SELECT COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END),0)
                 FROM ledger_entries e JOIN accounts a ON a.id=e.account_id
                WHERE a.type='CHECKING') AS deposits,
              (SELECT COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END),0)
                 FROM ledger_entries e JOIN accounts a ON a.id=e.account_id
                WHERE a.type='INVESTMENT') AS invested,
              (SELECT COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END),0)
                 FROM ledger_entries) AS ledger_balance
            """, Map.of(),
            (rs, n) -> new Metrics(rs.getLong("users"), rs.getLong("active_users"),
                    rs.getLong("transactions"), rs.getLong("open_loans"),
                    rs.getBigDecimal("deposits"), rs.getBigDecimal("invested"),
                    rs.getBigDecimal("ledger_balance")));
    }

    public record UserRow(UUID id, String fullName, String maskedCpf, String email,
                          String status, BigDecimal balance, Instant createdAt) {}

    public List<UserRow> users(int limit, int offset) {
        return jdbc.query("""
            SELECT u.id, u.full_name, u.cpf, u.email, u.status, u.created_at,
                   COALESCE((SELECT SUM(CASE WHEN e.direction='CREDIT' THEN e.amount ELSE -e.amount END)
                               + a.opening_balance
                              FROM accounts a
                              LEFT JOIN ledger_entries e ON e.account_id = a.id
                             WHERE a.owner_id = u.id AND a.type = 'CHECKING'
                             GROUP BY a.opening_balance), 0) AS balance
              FROM users u
             ORDER BY u.created_at DESC
             LIMIT :limit OFFSET :offset
            """, Map.of("limit", limit, "offset", offset),
            (rs, n) -> new UserRow(rs.getObject("id", UUID.class),
                    rs.getString("full_name"), maskCpf(rs.getString("cpf")),
                    rs.getString("email"), rs.getString("status"),
                    rs.getBigDecimal("balance"), rs.getTimestamp("created_at").toInstant()));
    }

    public record LedgerHealth(long totalEntries, long unbalancedTransactions,
                               BigDecimal globalSum) {}

    /** Integridade do razão: a soma global tem de ser zero. */
    public LedgerHealth ledgerHealth() {
        return jdbc.queryForObject("""
            SELECT
              (SELECT count(*) FROM ledger_entries) AS total,
              (SELECT count(*) FROM (
                 SELECT transaction_id FROM ledger_entries
                  GROUP BY transaction_id
                 HAVING SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END) <> 0
              ) x) AS unbalanced,
              (SELECT COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END),0)
                 FROM ledger_entries) AS global_sum
            """, Map.of(),
            (rs, n) -> new LedgerHealth(rs.getLong("total"),
                    rs.getLong("unbalanced"), rs.getBigDecimal("global_sum")));
    }

    public record RecentTx(String title, String counterparty, String category,
                           String method, boolean isCredit, BigDecimal amount,
                           Instant occurredAt) {}

    public List<RecentTx> recentTransactions(int limit) {
        return jdbc.query("""
            SELECT d.title, d.counterparty, d.category, d.method, d.is_credit,
                   d.amount, t.occurred_at
              FROM tx_details d JOIN transactions t ON t.id = d.transaction_id
             ORDER BY t.occurred_at DESC LIMIT :limit
            """, Map.of("limit", limit),
            (rs, n) -> new RecentTx(rs.getString("title"), rs.getString("counterparty"),
                    rs.getString("category"), rs.getString("method"),
                    rs.getBoolean("is_credit"), rs.getBigDecimal("amount"),
                    rs.getTimestamp("occurred_at").toInstant()));
    }

    private static String maskCpf(String cpf) {
        if (cpf == null || cpf.length() != 11) return "";
        return "***." + cpf.substring(3, 6) + "." + cpf.substring(6, 9) + "-**";
    }
}

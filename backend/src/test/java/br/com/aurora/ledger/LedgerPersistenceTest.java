package br.com.aurora.ledger;

import br.com.aurora.ledger.domain.*;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.*;

/**
 * Testa contra Postgres real, não H2: as garantias que mais importam aqui
 * (constraint DEFERRABLE, trigger append-only, tipos numeric) são
 * justamente as que um banco em memória não reproduz fielmente.
 */
@SpringBootTest
@Testcontainers
@EnabledIfSystemProperty(named = "testcontainers", matches = "true",
    disabledReason = """
        O Testcontainers não conecta no Docker Desktop 29 neste ambiente: o \
        cliente docker-java recebe HTTP 400 com corpo vazio e reporta \
        "Could not find a valid Docker environment". Enquanto isso, as mesmas \
        garantias são verificadas por scripts/verify-ledger.sql contra um \
        Postgres real. Para rodar: mvn test -Dtestcontainers=true""")
class LedgerPersistenceTest {

    @Container
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired LedgerRepository ledger;
    @Autowired NamedParameterJdbcTemplate jdbc;

    private final UUID tenant = UUID.randomUUID();
    private static final Instant WHEN = Instant.parse("2026-09-26T15:00:00Z");

    private UUID corrente;
    private UUID liquidacao;

    @BeforeEach
    void abrirContas() {
        var cc = Account.of(tenant, UUID.randomUUID(), AccountType.CHECKING, "Conta corrente");
        var liq = Account.of(tenant, null, AccountType.SETTLEMENT, "Liquidação Pix");
        ledger.saveAccount(cc);
        ledger.saveAccount(liq);
        corrente = cc.id();
        liquidacao = liq.id();
    }

    @Test
    @DisplayName("Saldo é derivado dos lançamentos, não armazenado")
    void saldoDerivado() {
        assertThat(ledger.balanceOf(corrente)).isEqualTo(Money.ZERO);

        // Entra salário.
        ledger.append(LedgerTransaction.transfer(tenant, "SALARIO", "Studio Nuvem",
                WHEN, liquidacao, corrente, Money.of("6200.00")));
        assertThat(ledger.balanceOf(corrente)).isEqualTo(Money.of("6200.00"));

        // Sai um Pix.
        ledger.append(LedgerTransaction.transfer(tenant, "PIX_ENVIADO", "Ana Luiza",
                WHEN, corrente, liquidacao, Money.of("60.00")));
        assertThat(ledger.balanceOf(corrente)).isEqualTo(Money.of("6140.00"));

        // A contraparte espelha exatamente o oposto: nada sumiu.
        assertThat(ledger.balanceOf(liquidacao)).isEqualTo(Money.of("-6140.00"));
    }

    @Test
    @DisplayName("Extrato vem na ordem canônica, do mais recente ao mais antigo")
    void extratoOrdenado() {
        ledger.append(LedgerTransaction.transfer(tenant, "SALARIO", "Studio Nuvem",
                WHEN, liquidacao, corrente, Money.of("6200.00")));
        ledger.append(LedgerTransaction.transfer(tenant, "PIX_ENVIADO", "Ana Luiza",
                WHEN, corrente, liquidacao, Money.of("60.00")));

        var extrato = ledger.statement(corrente, 10);

        assertThat(extrato).hasSize(2);
        assertThat(extrato.get(0).description()).isEqualTo("Ana Luiza");
        assertThat(extrato.get(0).direction()).isEqualTo(Direction.DEBIT);
        assertThat(extrato.get(1).description()).isEqualTo("Studio Nuvem");
        assertThat(extrato.get(0).sequence()).isGreaterThan(extrato.get(1).sequence());
    }

    @Test
    @DisplayName("I-1: o banco recusa uma transação desbalanceada no COMMIT")
    void bancoRecusaDesbalanceada() {
        // Contorna o domínio de propósito, inserindo SQL cru: é assim que se
        // prova que a garantia existe também no banco, e não só em Java.
        var txId = UUID.randomUUID();
        assertThatThrownBy(() -> inserirCru(txId, corrente, "DEBIT", "60.00", true))
                .hasMessageContaining("I-1");
    }

    @Test
    @DisplayName("ledger_entries é append-only: UPDATE e DELETE são recusados")
    void appendOnly() {
        ledger.append(LedgerTransaction.transfer(tenant, "SALARIO", "Studio Nuvem",
                WHEN, liquidacao, corrente, Money.of("100.00")));

        assertThatThrownBy(() ->
                jdbc.update("UPDATE ledger_entries SET amount = 1 WHERE account_id = :id",
                        Map.of("id", corrente)))
                .hasMessageContaining("append-only");

        assertThatThrownBy(() ->
                jdbc.update("DELETE FROM ledger_entries WHERE account_id = :id",
                        Map.of("id", corrente)))
                .hasMessageContaining("append-only");
    }

    @Test
    @DisplayName("Lançamento com valor negativo é recusado pelo CHECK")
    void valorNegativoRecusado() {
        var txId = UUID.randomUUID();
        assertThatThrownBy(() -> inserirCru(txId, corrente, "DEBIT", "-10.00", false))
                .hasMessageContaining("ledger_amount_positive");
    }

    /** Insere direto no SQL, sem passar pelo domínio. */
    private void inserirCru(UUID txId, UUID accountId, String direction,
                            String amount, boolean comTransacao) {
        if (comTransacao) {
            jdbc.update("""
                INSERT INTO transactions (id, tenant_id, kind, description, auth_code, occurred_at)
                VALUES (:id, :tenant, 'CRU', 'inserção crua', :auth, :when)
                """,
                Map.of("id", txId, "tenant", tenant,
                       "auth", "E" + UUID.randomUUID().toString().replace("-", "")
                                        .toUpperCase().substring(0, 31),
                       "when", java.sql.Timestamp.from(WHEN)));
        } else {
            jdbc.update("""
                INSERT INTO transactions (id, tenant_id, kind, description, auth_code, occurred_at)
                VALUES (:id, :tenant, 'CRU', 'inserção crua', :auth, :when)
                """,
                Map.of("id", txId, "tenant", tenant,
                       "auth", "E" + UUID.randomUUID().toString().replace("-", "")
                                        .toUpperCase().substring(0, 31),
                       "when", java.sql.Timestamp.from(WHEN)));
        }
        jdbc.update("""
            INSERT INTO ledger_entries (id, transaction_id, account_id, direction,
                                        amount, posted_at, effective_date)
            VALUES (:id, :tx, :acc, CAST(:dir AS entry_direction), :amt, :when, :date)
            """,
            Map.of("id", UUID.randomUUID(), "tx", txId, "acc", accountId,
                   "dir", direction, "amt", new java.math.BigDecimal(amount),
                   "when", java.sql.Timestamp.from(WHEN),
                   "date", java.sql.Date.valueOf("2026-09-26")));
    }
}

package br.com.aurora.ledger;

import br.com.aurora.ledger.domain.Entry;
import br.com.aurora.ledger.domain.LedgerTransaction;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Random;
import java.util.UUID;

import static org.assertj.core.api.Assertions.*;

/** As invariantes do ledger — o que impede dinheiro de sumir. */
class LedgerTransactionTest {

    private static final UUID TENANT = UUID.randomUUID();
    private static final Instant WHEN = Instant.parse("2026-09-26T12:00:00Z");
    private final UUID contaCorrente = UUID.randomUUID();
    private final UUID liquidacao = UUID.randomUUID();

    @Test
    @DisplayName("I-1: transação balanceada é aceita")
    void aceitaTransacaoBalanceada() {
        var tx = LedgerTransaction.transfer(TENANT, "PIX_ENVIADO", "Pix para Ana",
                WHEN, contaCorrente, liquidacao, Money.of("60.00"));

        assertThat(tx.entries()).hasSize(2);
        assertThat(tx.effectOn(contaCorrente)).isEqualTo(Money.of("-60.00"));
        assertThat(tx.effectOn(liquidacao)).isEqualTo(Money.of("60.00"));
    }

    @Test
    @DisplayName("I-1: transação desbalanceada é recusada no construtor")
    void recusaTransacaoDesbalanceada() {
        assertThatThrownBy(() -> LedgerTransaction.of(TENANT, "QUEBRADA", "não soma zero", WHEN,
                List.of(Entry.debit(contaCorrente, Money.of("60.00")),
                        Entry.credit(liquidacao, Money.of("59.99")))))
                .isInstanceOf(DomainException.class)
                .extracting(e -> ((DomainException) e).code())
                .isEqualTo(ErrorCode.LANCAMENTO_DESBALANCEADO);
    }

    @Test
    @DisplayName("I-2: transação com uma perna só é recusada")
    void recusaPernaUnica() {
        assertThatThrownBy(() -> LedgerTransaction.of(TENANT, "SOLTA", "uma perna", WHEN,
                List.of(Entry.debit(contaCorrente, Money.of("10.00")))))
                .isInstanceOf(DomainException.class)
                .extracting(e -> ((DomainException) e).code())
                .isEqualTo(ErrorCode.PERNAS_INSUFICIENTES);
    }

    @Test
    @DisplayName("I-2: pernas na mesma conta são recusadas")
    void recusaMesmaConta() {
        assertThatThrownBy(() -> LedgerTransaction.of(TENANT, "CIRCULAR", "mesma conta", WHEN,
                List.of(Entry.debit(contaCorrente, Money.of("10.00")),
                        Entry.credit(contaCorrente, Money.of("10.00")))))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("Lançamento com valor zero ou negativo é recusado")
    void recusaValorNaoPositivo() {
        assertThatThrownBy(() -> Entry.debit(contaCorrente, Money.ZERO))
                .isInstanceOf(DomainException.class)
                .extracting(e -> ((DomainException) e).code())
                .isEqualTo(ErrorCode.VALOR_NAO_POSITIVO);

        assertThatThrownBy(() -> Entry.credit(contaCorrente, Money.of("-5.00")))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("Transação de várias pernas soma zero (ex.: compra com cashback)")
    void aceitaMultiplasPernas() {
        var despesa = UUID.randomUUID();
        var receita = UUID.randomUUID();
        var tx = LedgerTransaction.of(TENANT, "COMPRA", "Mercado com cashback", WHEN,
                List.of(Entry.debit(despesa, Money.of("87.40")),
                        Entry.credit(contaCorrente, Money.of("1.75")),
                        Entry.credit(receita, Money.of("85.65"))));

        assertThat(tx.entries()).hasSize(3);
    }

    @Test
    @DisplayName("Propriedade: mil transações aleatórias, saldo global sempre zero")
    void propriedadeSomaZeroGlobal() {
        var rnd = new Random(42);            // semente fixa: teste determinístico
        var contas = List.of(UUID.randomUUID(), UUID.randomUUID(),
                             UUID.randomUUID(), UUID.randomUUID());
        Money global = Money.ZERO;

        for (int i = 0; i < 1_000; i++) {
            int a = rnd.nextInt(contas.size());
            int b = (a + 1 + rnd.nextInt(contas.size() - 1)) % contas.size();
            var valor = Money.ofCents(1 + rnd.nextInt(1_000_000));

            var tx = LedgerTransaction.transfer(TENANT, "ALEATORIA", "teste", WHEN,
                    contas.get(a), contas.get(b), valor);

            for (var conta : contas) {
                global = global.plus(tx.effectOn(conta));
            }
        }
        assertThat(global).isEqualTo(Money.ZERO);
    }
}

package br.com.aurora.banking;

import br.com.aurora.banking.domain.Boleto;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.money.Money;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.*;

/** Decodificação da linha digitável, com dígitos verificadores de verdade. */
class BoletoTest {

    /** Monta uma linha válida para um dado fator e valor. */
    private static String line(int factor, long cents) {
        String bank = "341", currency = "9";
        String free = "0".repeat(25);
        String c1 = bank + currency + free.substring(0, 5);
        String c2 = free.substring(5, 15);
        String c3 = free.substring(15, 25);
        return c1 + mod10(c1) + c2 + mod10(c2) + c3 + mod10(c3)
             + "1" + String.format("%04d%010d", factor, cents);
    }

    private static int mod10(String block) {
        int sum = 0, weight = 2;
        for (int i = block.length() - 1; i >= 0; i--) {
            int p = (block.charAt(i) - '0') * weight;
            sum += p > 9 ? p - 9 : p;
            weight = weight == 2 ? 1 : 2;
        }
        return (10 - (sum % 10)) % 10;
    }

    @Test
    @DisplayName("Linha válida devolve banco, valor e vencimento")
    void decodificaLinhaValida() {
        // Fator 1236 no ciclo novo: 22/02/2025 + 236 dias.
        var boleto = Boleto.parse(line(1236, 18740), LocalDate.of(2025, 10, 1));

        assertThat(boleto.bankCode()).isEqualTo("341");
        assertThat(boleto.payee()).isEqualTo("Itaú Unibanco");
        assertThat(boleto.amount()).isEqualTo(Money.of("187.40"));
        assertThat(boleto.dueDate()).isEqualTo(LocalDate.of(2025, 2, 22).plusDays(236));
        assertThat(boleto.kind()).isEqualTo(Boleto.BoletoKind.BANCARIO);
    }

    @Test
    @DisplayName("A linha aceita máscara com pontos e espaços")
    void aceitaMascara() {
        String raw = line(1236, 18740);
        String masked = raw.substring(0, 5) + "." + raw.substring(5, 10) + " "
                      + raw.substring(10, 20) + " " + raw.substring(20);

        assertThat(Boleto.parse(masked, LocalDate.of(2025, 10, 1)).amount())
                .isEqualTo(Money.of("187.40"));
    }

    @Test
    @DisplayName("Dígito verificador errado é recusado")
    void recusaDigitoErrado() {
        var chars = line(1236, 18740).toCharArray();
        chars[9] = chars[9] == '0' ? '1' : '0';    // estraga o DV do 1º campo

        assertThatThrownBy(() -> Boleto.parse(new String(chars)))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("primeiro campo");
    }

    @Test
    @DisplayName("Tamanho fora de 47 ou 48 dígitos é recusado")
    void recusaTamanhoInvalido() {
        assertThatThrownBy(() -> Boleto.parse("123456"))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("47 ou 48");
        assertThatThrownBy(() -> Boleto.parse(null))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("A virada do fator de vencimento de 2025 é respeitada")
    void viradaDoFator() {
        // O contador de 4 dígitos esgotou em 21/02/2025 com fator 9999 e
        // reiniciou em 1000. Sem tratar isso, um boleto de hoje cairia 27
        // anos no passado.
        // Lendo em fev/2025, o fator 9999 ainda é do ciclo antigo.
        assertThat(Boleto.dueDateFromFactor(9999, LocalDate.of(2025, 2, 20)))
                .isEqualTo(LocalDate.of(2025, 2, 21));
        // Lendo depois da virada, 1000 é a nova data-base.
        assertThat(Boleto.dueDateFromFactor(1000, LocalDate.of(2025, 3, 1)))
                .isEqualTo(LocalDate.of(2025, 2, 22));
        assertThat(Boleto.dueDateFromFactor(1001, LocalDate.of(2025, 3, 1)))
                .isEqualTo(LocalDate.of(2025, 2, 23));

        // Fator abaixo de 1000 só existiu no ciclo antigo, sem ambiguidade.
        assertThat(Boleto.dueDateFromFactor(999, LocalDate.of(2026, 1, 1)))
                .isEqualTo(LocalDate.of(2000, 7, 2));
    }

    @Test
    @DisplayName("Fator zero significa boleto sem vencimento")
    void fatorZeroSemVencimento() {
        assertThat(Boleto.dueDateFromFactor(0, LocalDate.of(2026, 1, 1))).isNull();
        assertThat(Boleto.parse(line(0, 5000), LocalDate.of(2026, 1, 1)).dueDate()).isNull();
    }

    // ------------------------------------------------- arrecadação (48)

    /** Monta uma linha de arrecadação válida para um dado valor. */
    private static String arrecadacao(char valueId, long cents) {
        // Código de barras: 8 + segmento + idValor + DV + valor(11) + livre(30)
        String barcode = "8" + "3" + valueId + "0"
                + String.format("%011d", cents) + "0".repeat(30);
        boolean mod11 = valueId == '8' || valueId == '9';

        var line = new StringBuilder(48);
        for (int b = 0; b < 4; b++) {
            String data = barcode.substring(b * 11, b * 11 + 11);
            line.append(data).append(mod11 ? mod11Dv(data) : mod10(data));
        }
        return line.toString();
    }

    private static int mod11Dv(String block) {
        int sum = 0, weight = 2;
        for (int i = block.length() - 1; i >= 0; i--) {
            sum += (block.charAt(i) - '0') * weight;
            weight = weight == 9 ? 2 : weight + 1;
        }
        int rest = sum % 11;
        return switch (rest) { case 0, 1 -> 0; case 10 -> 1; default -> 11 - rest; };
    }

    @Test
    @DisplayName("Arrecadação com módulo 10: valor vem do código de barras")
    void arrecadacaoMod10() {
        // O valor fica no código de barras remontado, não na linha crua —
        // ler direto da linha atravessaria os dígitos verificadores.
        var boleto = Boleto.parse(arrecadacao('6', 18740));

        assertThat(boleto.kind()).isEqualTo(Boleto.BoletoKind.ARRECADACAO);
        assertThat(boleto.amount()).isEqualTo(Money.of("187.40"));
        assertThat(boleto.payee()).isEqualTo("Energia elétrica e gás");
    }

    @Test
    @DisplayName("Arrecadação com módulo 11 é aceita")
    void arrecadacaoMod11() {
        // Identificador 8 exige módulo 11; com módulo 10 seria recusada.
        var boleto = Boleto.parse(arrecadacao('8', 9420));
        assertThat(boleto.amount()).isEqualTo(Money.of("94.20"));
    }

    @Test
    @DisplayName("Arrecadação com DV errado é recusada")
    void arrecadacaoDvErrado() {
        var chars = arrecadacao('6', 18740).toCharArray();
        chars[11] = chars[11] == '0' ? '1' : '0';    // DV do primeiro bloco

        assertThatThrownBy(() -> Boleto.parse(new String(chars)))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("bloco 1");
    }

    @Test
    @DisplayName("Identificador de valor inválido é recusado")
    void arrecadacaoIdInvalido() {
        assertThatThrownBy(() -> Boleto.parse(arrecadacao('1', 1000)))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("Boleto vencido é identificado")
    void identificaVencido() {
        var boleto = Boleto.parse(line(1100, 10000), LocalDate.of(2025, 7, 1));
        assertThat(boleto.isOverdue(LocalDate.of(2026, 1, 1))).isTrue();
        assertThat(boleto.isOverdue(LocalDate.of(2025, 1, 1))).isFalse();
    }
}

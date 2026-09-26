package br.com.aurora.shared;

import br.com.aurora.shared.money.Money;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class MoneyTest {

    @Test
    @DisplayName("Centavos não acumulam erro — o motivo de não usar double")
    void semErroDePontoFlutuante() {
        Money total = Money.ZERO;
        for (int i = 0; i < 10; i++) {
            total = total.plus(Money.of("0.10"));
        }
        assertThat(total).isEqualTo(Money.of("1.00"));
        assertThat(total.cents()).isEqualTo(100L);

        // A mesma soma em double erraria:
        double d = 0;
        for (int i = 0; i < 10; i++) d += 0.10;
        assertThat(d).isNotEqualTo(1.0);
    }

    @Test
    @DisplayName("Escala é sempre 2, com arredondamento bancário")
    void escalaFixa() {
        assertThat(Money.of("1.005").cents()).isEqualTo(100L);   // HALF_EVEN
        assertThat(Money.of("1.015").cents()).isEqualTo(102L);
        assertThat(Money.of("3").toString()).isEqualTo("R$ 3.00");
    }

    @Test
    @DisplayName("Conversão para centavos e de volta é estável")
    void centavosIdaEVolta() {
        var m = Money.of("4280.55");
        assertThat(Money.ofCents(m.cents())).isEqualTo(m);
        assertThat(m.cents()).isEqualTo(428055L);
    }
}

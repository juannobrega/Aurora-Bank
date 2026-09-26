package br.com.aurora.banking;

import br.com.aurora.banking.domain.Carrier;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.money.Money;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.*;

class CarrierTest {

    @Test
    @DisplayName("Identifica a operadora pelo prefixo")
    void identificaOperadora() {
        assertThat(Carrier.of("11971234567")).isEqualTo(Carrier.VIVO);
        assertThat(Carrier.of("11981234567")).isEqualTo(Carrier.CLARO);
        assertThat(Carrier.of("11991234567")).isEqualTo(Carrier.TIM);
        assertThat(Carrier.of("11931234567")).isEqualTo(Carrier.OI);
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "1199123456",     // 10 dígitos, faltando um
        "119912345678",   // 12 dígitos
        "0199123456789",  // DDD inválido
        "11891234567"     // não começa com 9 depois do DDD
    })
    @DisplayName("Número fora do padrão é recusado")
    void recusaNumeroInvalido(String phone) {
        assertThatThrownBy(() -> Carrier.validate(phone))
                .isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("Máscara é aceita e normalizada")
    void aceitaMascara() {
        assertThat(Carrier.validate("(11) 99873-3120")).isEqualTo("11998733120");
        assertThat(Carrier.format("11998733120")).isEqualTo("(11) 99873-3120");
    }

    @Test
    @DisplayName("Só valores da tabela da operadora são aceitos")
    void validaValorRecarga() {
        assertThatCode(() -> Carrier.checkAmount(Money.of("20.00")))
                .doesNotThrowAnyException();
        assertThatThrownBy(() -> Carrier.checkAmount(Money.of("17.35")))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("Valores disponíveis");
    }
}

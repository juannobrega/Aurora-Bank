package br.com.aurora.identity;

import br.com.aurora.identity.domain.Cpf;
import br.com.aurora.identity.domain.Pin;
import br.com.aurora.shared.error.DomainException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.*;

class CpfAndPinTest {

    @ParameterizedTest
    @ValueSource(strings = {"529.982.247-25", "52998224725", "111.444.777-35"})
    @DisplayName("CPF com dígitos verificadores corretos é aceito")
    void cpfValido(String cpf) {
        assertThat(Cpf.isValid(cpf)).isTrue();
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "529.982.247-26",   // dígito verificador errado
        "111.111.111-11",   // todos iguais
        "123",              // curto demais
        "abcdefghijk"       // sem dígitos
    })
    @DisplayName("CPF inválido é recusado")
    void cpfInvalido(String cpf) {
        assertThat(Cpf.isValid(cpf)).isFalse();
        assertThatThrownBy(() -> Cpf.normalize(cpf)).isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("Normalizar remove a máscara e mantém só dígitos")
    void normalizaCpf() {
        assertThat(Cpf.normalize("529.982.247-25")).isEqualTo("52998224725");
    }

    @ParameterizedTest
    @ValueSource(strings = {"1111", "0000", "1234", "4321", "6789", "3210"})
    @DisplayName("PIN previsível é recusado")
    void pinFraco(String pin) {
        assertThat(Pin.isWeak(pin)).isTrue();
        assertThatThrownBy(() -> Pin.validate(pin)).isInstanceOf(DomainException.class);
    }

    @ParameterizedTest
    @ValueSource(strings = {"2846", "9137", "5028"})
    @DisplayName("PIN sem padrão óbvio é aceito")
    void pinForte(String pin) {
        assertThat(Pin.isWeak(pin)).isFalse();
        assertThatCode(() -> Pin.validate(pin)).doesNotThrowAnyException();
    }

    @ParameterizedTest
    @ValueSource(strings = {"123", "12345", "abcd", ""})
    @DisplayName("PIN fora do formato de 4 dígitos é recusado")
    void pinFormatoInvalido(String pin) {
        assertThatThrownBy(() -> Pin.validate(pin))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("4 dígitos");
    }
}

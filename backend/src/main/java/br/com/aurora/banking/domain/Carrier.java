package br.com.aurora.banking.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;

import java.util.List;
import java.util.Set;

/**
 * Operadora de celular, identificada pelo prefixo do número.
 *
 * <p>Na vida real isso vem de consulta à ABR Telecom, porque portabilidade
 * quebra a relação prefixo→operadora. Aqui a tabela é estática e o código
 * diz isso abertamente, em vez de fingir precisão que não tem.
 */
public enum Carrier {
    // Faixas aproximadas do quinto dígito do número (após DDD + 9).
    VIVO("Vivo", Set.of("6","7")),
    CLARO("Claro", Set.of("8")),
    TIM("TIM", Set.of("9","5")),
    OI("Oi", Set.of("3","4"));

    private final String label;
    private final Set<String> prefixes;

    Carrier(String label, Set<String> prefixes) {
        this.label = label;
        this.prefixes = prefixes;
    }

    public String label() { return label; }

    /** Valores de recarga aceitos, como nas operadoras de verdade. */
    public static final List<Money> ALLOWED_AMOUNTS = List.of(
            Money.of("15.00"), Money.of("20.00"), Money.of("25.00"),
            Money.of("30.00"), Money.of("35.00"), Money.of("50.00"),
            Money.of("100.00"));

    /**
     * Descobre a operadora pelos dois dígitos após o DDD.
     *
     * @param phone 11 dígitos: DD + 9 + 8 dígitos
     */
    public static Carrier of(String phone) {
        String digits = validate(phone);
        String key = digits.substring(3, 4);   // primeiro dígito após o 9
        for (Carrier c : values()) {
            if (c.prefixes.contains(key)) return c;
        }
        // Prefixo desconhecido: assume a maior operadora em vez de falhar,
        // porque portabilidade torna o mapeamento aproximado de qualquer jeito.
        return VIVO;
    }

    /** Valida o formato e devolve só os dígitos. */
    public static String validate(String phone) {
        if (phone == null) throw new DomainException(ErrorCode.TELEFONE_INVALIDO);
        String digits = phone.replaceAll("\\D", "");

        if (digits.length() != 11) {
            throw new DomainException(ErrorCode.TELEFONE_INVALIDO,
                    "Informe DDD e número com 11 dígitos.");
        }
        int ddd = Integer.parseInt(digits.substring(0, 2));
        if (ddd < 11 || ddd > 99) {
            throw new DomainException(ErrorCode.TELEFONE_INVALIDO, "DDD inexistente.");
        }
        if (digits.charAt(2) != '9') {
            throw new DomainException(ErrorCode.TELEFONE_INVALIDO,
                    "Celular no Brasil começa com 9 depois do DDD.");
        }
        return digits;
    }

    public static void checkAmount(Money amount) {
        if (!ALLOWED_AMOUNTS.contains(amount)) {
            throw new DomainException(ErrorCode.VALOR_RECARGA_INVALIDO,
                    "Valores disponíveis: " + ALLOWED_AMOUNTS);
        }
    }

    /** Formata para exibição: (11) 99873-3120 */
    public static String format(String digits) {
        return "(" + digits.substring(0, 2) + ") " + digits.substring(2, 7)
             + "-" + digits.substring(7);
    }
}

package br.com.aurora.banking.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Boleto lido da linha digitável.
 *
 * <p>A linha digitável não é um código opaco: ela carrega banco, moeda,
 * vencimento e valor, com dígitos verificadores em cada bloco. Decodificar
 * de verdade — em vez de sortear dados como o protótipo fazia — é o que
 * permite recusar um código digitado errado antes de cobrar alguém.
 */
public record Boleto(
        String digitableLine,
        String bankCode,
        Money amount,
        LocalDate dueDate,
        BoletoKind kind,
        String payee
) {
    public enum BoletoKind {
        /** Cobrança bancária: 47 dígitos, começa com o código do banco. */
        BANCARIO,
        /** Conta de consumo e tributo: 48 dígitos, começa com 8. */
        ARRECADACAO
    }

    /**
     * Data-base original do fator de vencimento (FEBRABAN).
     * O contador de 4 dígitos esgotou em 21/02/2025, com fator 9999.
     */
    private static final LocalDate FACTOR_EPOCH = LocalDate.of(1997, 10, 7);

    /**
     * Após esgotar, o fator reiniciou em 1000 valendo 22/02/2025. Sem
     * tratar isso, todo boleto emitido a partir dessa data cairia ~27 anos
     * no passado.
     */
    private static final LocalDate FACTOR_EPOCH_V2 = LocalDate.of(2025, 2, 22);
    private static final int FACTOR_V2_START = 1000;

    public boolean isOverdue(LocalDate today) {
        return dueDate != null && dueDate.isBefore(today);
    }

    /**
     * Decodifica a linha digitável.
     *
     * @throws DomainException se o formato, o tamanho ou os dígitos
     *         verificadores não baterem.
     */
    public static Boleto parse(String raw) {
        return parse(raw, LocalDate.now(AuroraClockRef.ZONE));
    }

    /** @param today referência para desambiguar o fator de vencimento */
    public static Boleto parse(String raw, LocalDate today) {
        if (raw == null) throw new DomainException(ErrorCode.BOLETO_INVALIDO);
        String digits = raw.replaceAll("\\D", "");

        return switch (digits.length()) {
            case 47 -> parseBancario(digits, today);
            case 48 -> parseArrecadacao(digits);
            default -> throw new DomainException(ErrorCode.BOLETO_INVALIDO,
                    "A linha digitável deve ter 47 ou 48 dígitos; recebidos "
                    + digits.length() + ".");
        };
    }

    /**
     * Cobrança bancária (47 dígitos), dividida em três campos com dígito
     * verificador módulo 10 e um campo livre.
     *
     * <p>Posições: 0-8 e 9 (DV), 10-19 e 20 (DV), 21-30 e 31 (DV),
     * 32 (DV geral), 33-36 (fator de vencimento), 37-46 (valor).
     */
    private static Boleto parseBancario(String d, LocalDate today) {
        checkMod10(d.substring(0, 9),   d.charAt(9),  "primeiro campo");
        checkMod10(d.substring(10, 20), d.charAt(20), "segundo campo");
        checkMod10(d.substring(21, 31), d.charAt(31), "terceiro campo");

        LocalDate due = dueDateFromFactor(Integer.parseInt(d.substring(33, 37)), today);

        var amount = new Money(new BigDecimal(d.substring(37, 47)).movePointLeft(2));
        String bank = d.substring(0, 3);

        return new Boleto(d, bank, amount, due, BoletoKind.BANCARIO, payeeFor(bank));
    }

    /**
     * Arrecadação (48 dígitos): quatro blocos de 11 dígitos, cada um com
     * seu DV. O terceiro dígito indica se o valor é efetivo ou referência.
     */
    private static Boleto parseArrecadacao(String d) {
        if (d.charAt(0) != '8') {
            throw new DomainException(ErrorCode.BOLETO_INVALIDO,
                    "Conta de consumo e tributo começa com 8.");
        }
        // Cada bloco de 12 traz 11 dígitos de dado e 1 de verificação.
        for (int block = 0; block < 4; block++) {
            int start = block * 12;
            checkMod10(d.substring(start, start + 11), d.charAt(start + 11),
                    "bloco " + (block + 1));
        }
        var amount = new Money(new BigDecimal(d.substring(4, 15)).movePointLeft(2));
        return new Boleto(d, d.substring(1, 2), amount, null,
                BoletoKind.ARRECADACAO, "Conta de consumo");
    }

    /**
     * Converte o fator de vencimento em data.
     *
     * <p>A faixa 1000–9999 é <b>ambígua</b>: ela existiu no ciclo antigo
     * (1000 = 03/07/2000, 9999 = 21/02/2025) e voltou a existir no novo
     * (1000 = 22/02/2025). O desempate é a data em que se está lendo o
     * boleto: um vencimento no passado distante não faz sentido para um
     * boleto que se está pagando agora.
     *
     * @param today data de referência, vinda do relógio injetado
     */
    public static LocalDate dueDateFromFactor(int factor, LocalDate today) {
        if (factor == 0) return null;                     // sem vencimento

        LocalDate oldCycle = FACTOR_EPOCH.plusDays(factor);
        LocalDate newCycle = FACTOR_EPOCH_V2.plusDays(factor - FACTOR_V2_START);

        // Fator abaixo de 1000 só existiu no ciclo antigo.
        if (factor < FACTOR_V2_START) return oldCycle;

        // Boleto se paga perto do vencimento: escolhe o ciclo cuja data
        // está mais próxima de hoje, com folga para boletos vencidos.
        long distOld = Math.abs(java.time.temporal.ChronoUnit.DAYS.between(oldCycle, today));
        long distNew = Math.abs(java.time.temporal.ChronoUnit.DAYS.between(newCycle, today));
        return distNew <= distOld ? newCycle : oldCycle;
    }

    /** Usa a data de hoje do sistema como referência. */
    public static LocalDate dueDateFromFactor(int factor) {
        return dueDateFromFactor(factor, LocalDate.now(AuroraClockRef.ZONE));
    }

    /** Fuso de Brasília, para não depender do fuso da máquina. */
    private static final class AuroraClockRef {
        static final java.time.ZoneId ZONE = java.time.ZoneId.of("America/Sao_Paulo");
    }

    /**
     * Módulo 10 da FEBRABAN: pesos 2 e 1 alternados da direita para a
     * esquerda, somando os algarismos de cada produto.
     */
    static void checkMod10(String block, char expected, String label) {
        int sum = 0, weight = 2;
        for (int i = block.length() - 1; i >= 0; i--) {
            int product = (block.charAt(i) - '0') * weight;
            sum += product > 9 ? product - 9 : product;
            weight = weight == 2 ? 1 : 2;
        }
        int dv = (10 - (sum % 10)) % 10;
        if (dv != expected - '0') {
            throw new DomainException(ErrorCode.BOLETO_INVALIDO,
                    "Dígito verificador do " + label + " não confere.");
        }
    }

    /** Nome do beneficiário a partir do código do banco (tabela FEBRABAN). */
    private static String payeeFor(String bankCode) {
        return switch (bankCode) {
            case "001" -> "Banco do Brasil";
            case "033" -> "Santander";
            case "104" -> "Caixa Econômica Federal";
            case "237" -> "Bradesco";
            case "341" -> "Itaú Unibanco";
            case "260" -> "Nu Pagamentos";
            case "077" -> "Banco Inter";
            case "336" -> "C6 Bank";
            default -> "Banco " + bankCode;
        };
    }
}

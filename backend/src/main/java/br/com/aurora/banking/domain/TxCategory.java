package br.com.aurora.banking.domain;

/** Espelha o enum Category do app iOS. */
public enum TxCategory {
    moradia, mercado, restaurantes, transporte, assinaturas, saude,
    educacao, lazer, transferencia, investimento, salario, rendimento,
    credito, outros;

    /**
     * Entra no orçamento mensal de despesas? Regra de negócio, não
     * cosmética: o gráfico de gastos e o orçamento dependem dela.
     */
    public boolean isSpending() {
        return switch (this) {
            case salario, rendimento, credito, investimento -> false;
            default -> true;
        };
    }
}

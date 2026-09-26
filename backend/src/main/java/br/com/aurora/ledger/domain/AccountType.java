package br.com.aurora.ledger.domain;

/**
 * Tipos de conta interna. O dinheiro nunca "some": ele muda de conta.
 * Um cofrinho, por exemplo, é uma conta {@code GOAL} — não um campo
 * {@code saved} solto, como era no protótipo.
 */
public enum AccountType {
    /** Conta corrente do cliente. */
    CHECKING,
    /** Cofrinho: reserva com objetivo. */
    GOAL,
    /** Posição em um produto de investimento. */
    INVESTMENT,
    /** Fatura em aberto do cartão — seu saldo É a fatura. */
    CARD_LIABILITY,
    /** Saldo devedor de um contrato de empréstimo. */
    LOAN_LIABILITY,
    /** Conta de liquidação (Pix, TED, boleto) — contraparte externa. */
    SETTLEMENT,
    /** Receita e despesa do próprio banco. */
    REVENUE,
    EXPENSE,
    /** Funding do banco, contraparte de desembolsos. */
    FUNDING;

    /** Contas do cliente não podem ficar negativas sem contrato. */
    public boolean isCustomerAsset() {
        return this == CHECKING || this == GOAL || this == INVESTMENT;
    }
}

package br.com.aurora.ledger.domain;

/**
 * Sentido do lançamento. O valor de um lançamento é <b>sempre positivo</b>;
 * o sinal vive aqui. Isso evita a ambiguidade de "menos cem" significar
 * coisas diferentes em contas de ativo e de passivo.
 */
public enum Direction {
    DEBIT, CREDIT;

    public Direction opposite() {
        return this == DEBIT ? CREDIT : DEBIT;
    }
}

package br.com.aurora.identity.domain;

/** Ciclo de vida da conta. Só ACTIVE pode movimentar dinheiro. */
public enum UserStatus {
    /** Cadastro iniciado, rosto ainda não validado. */
    PENDING_KYC,
    ACTIVE,
    BLOCKED,
    CLOSED
}

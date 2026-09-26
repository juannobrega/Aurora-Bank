package br.com.aurora.identity.domain;

public enum DeviceStatus {
    /** Registrado, aguardando a primeira autenticação completa. */
    PENDING,
    TRUSTED,
    REVOKED
}

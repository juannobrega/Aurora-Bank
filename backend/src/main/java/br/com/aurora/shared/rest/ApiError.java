package br.com.aurora.shared.rest;

import java.time.Instant;

/** Formato único de erro da API. Mensagem sempre em pt-BR, legível. */
public record ApiError(String code, String message, String field,
                       String traceId, Instant timestamp) {

    public static ApiError of(String code, String message, String traceId) {
        return new ApiError(code, message, null, traceId, Instant.now());
    }
}

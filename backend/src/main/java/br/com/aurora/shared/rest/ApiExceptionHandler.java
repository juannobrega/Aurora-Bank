package br.com.aurora.shared.rest;

import br.com.aurora.shared.error.DomainException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.UUID;

/**
 * Traduz exceções para o formato de erro da API.
 *
 * <p>Centralizar aqui evita que cada controller monte erro na mão — e
 * garante que nenhuma exceção inesperada vaze stack trace para o cliente.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(DomainException.class)
    public ResponseEntity<ApiError> handleDomain(DomainException e) {
        var traceId = UUID.randomUUID().toString();
        // Erro de domínio é esperado: registra em nível baixo, sem stack.
        log.info("[{}] {} — {}", traceId, e.code(), e.getMessage());
        return ResponseEntity.status(e.code().status())
                .body(ApiError.of(e.code().name(), e.getMessage(), traceId));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> handleValidation(MethodArgumentNotValidException e) {
        var traceId = UUID.randomUUID().toString();
        var fieldError = e.getBindingResult().getFieldErrors().stream().findFirst();
        String field = fieldError.map(f -> f.getField()).orElse(null);
        String message = fieldError.map(f -> f.getDefaultMessage())
                .orElse("Requisição inválida.");
        return ResponseEntity.badRequest()
                .body(new ApiError("REQUISICAO_INVALIDA", message, field,
                        traceId, java.time.Instant.now()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleUnexpected(Exception e) {
        var traceId = UUID.randomUUID().toString();
        // Inesperado: registra tudo no servidor, devolve pouco ao cliente.
        log.error("[{}] erro não tratado", traceId, e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiError.of("ERRO_INTERNO",
                        "Algo deu errado do nosso lado. Tente de novo.", traceId));
    }
}

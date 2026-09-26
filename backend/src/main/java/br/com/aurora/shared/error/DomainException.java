package br.com.aurora.shared.error;

/** Erro de regra de negócio. O código vira o {@code code} da resposta HTTP. */
public class DomainException extends RuntimeException {

    private final ErrorCode code;

    public DomainException(ErrorCode code) {
        super(code.message());
        this.code = code;
    }

    public DomainException(ErrorCode code, String detail) {
        super(code.message() + " " + detail);
        this.code = code;
    }

    public ErrorCode code() { return code; }
}

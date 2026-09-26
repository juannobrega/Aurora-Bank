package br.com.aurora.shared.error;

import org.springframework.http.HttpStatus;

/** Catálogo de erros do domínio, com mensagem em pt-BR para o cliente. */
public enum ErrorCode {

    // Ledger
    LANCAMENTO_DESBALANCEADO(HttpStatus.INTERNAL_SERVER_ERROR,
        "Os lançamentos da transação não somam zero."),
    PERNAS_INSUFICIENTES(HttpStatus.INTERNAL_SERVER_ERROR,
        "Uma transação precisa de ao menos duas pernas em contas distintas."),
    VALOR_NAO_POSITIVO(HttpStatus.BAD_REQUEST,
        "O valor de um lançamento deve ser positivo."),
    CONTA_NAO_ENCONTRADA(HttpStatus.NOT_FOUND,
        "Conta não encontrada."),

    // Saldo
    SALDO_INSUFICIENTE(HttpStatus.UNPROCESSABLE_ENTITY,
        "Saldo insuficiente."),
    LIMITE_NOTURNO_EXCEDIDO(HttpStatus.UNPROCESSABLE_ENTITY,
        "Valor acima do limite noturno."),

    // Idempotência
    IDEMPOTENCIA_EM_ANDAMENTO(HttpStatus.CONFLICT,
        "Uma requisição com esta chave ainda está em processamento."),
    IDEMPOTENCIA_CONFLITO(HttpStatus.UNPROCESSABLE_ENTITY,
        "Esta chave de idempotência já foi usada com outro conteúdo.");

    private final HttpStatus status;
    private final String message;

    ErrorCode(HttpStatus status, String message) {
        this.status = status;
        this.message = message;
    }

    public HttpStatus status()  { return status; }
    public String message()     { return message; }
}

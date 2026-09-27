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
    PIX_PARA_SI_MESMO(HttpStatus.UNPROCESSABLE_ENTITY,
        "Esta chave é sua. Escolha outro destinatário."),
    PIX_NAO_DEVOLVIVEL(HttpStatus.UNPROCESSABLE_ENTITY,
        "Só um Pix recebido pode ser devolvido."),

    // Identidade e biometria
    CPF_INVALIDO(HttpStatus.BAD_REQUEST,
        "CPF inválido."),
    CPF_JA_CADASTRADO(HttpStatus.CONFLICT,
        "Já existe uma conta com este CPF."),
    EMAIL_JA_CADASTRADO(HttpStatus.CONFLICT,
        "Já existe uma conta com este e-mail."),
    USUARIO_NAO_ENCONTRADO(HttpStatus.NOT_FOUND,
        "Usuário não encontrado."),
    BIOMETRIA_INVALIDA(HttpStatus.BAD_REQUEST,
        "Os dados biométricos enviados são inválidos."),
    BIOMETRIA_NAO_CADASTRADA(HttpStatus.UNPROCESSABLE_ENTITY,
        "Este usuário ainda não tem rosto cadastrado."),
    BIOMETRIA_JA_CADASTRADA(HttpStatus.CONFLICT,
        "Este usuário já tem um rosto cadastrado."),
    PROVA_DE_VIDA_REPROVADA(HttpStatus.UNPROCESSABLE_ENTITY,
        "Não foi possível confirmar que é uma pessoa real. Tente em local bem iluminado."),
    ROSTO_NAO_CONFERE(HttpStatus.UNAUTHORIZED,
        "O rosto não confere com o cadastrado."),
    QUALIDADE_INSUFICIENTE(HttpStatus.UNPROCESSABLE_ENTITY,
        "A captura ficou com qualidade baixa. Centralize o rosto e melhore a iluminação."),
    KYC_PENDENTE(HttpStatus.FORBIDDEN,
        "Conclua a validação facial para ativar a conta."),
    PIN_INCORRETO(HttpStatus.UNAUTHORIZED,
        "PIN incorreto."),
    PIN_FRACO(HttpStatus.BAD_REQUEST,
        "PIN muito fácil de adivinhar. Evite sequências e dígitos repetidos."),
    CONTA_BLOQUEADA(HttpStatus.FORBIDDEN,
        "Conta temporariamente bloqueada por tentativas incorretas."),
    DISPOSITIVO_NAO_RECONHECIDO(HttpStatus.FORBIDDEN,
        "Dispositivo não reconhecido."),
    DISPOSITIVO_REVOGADO(HttpStatus.FORBIDDEN,
        "O acesso deste aparelho foi revogado."),
    SESSAO_EXPIRADA(HttpStatus.UNAUTHORIZED,
        "Sua sessão expirou. Entre novamente."),
    AUTENTICACAO_FRACA(HttpStatus.FORBIDDEN,
        "Confirme seu PIN ou biometria para concluir esta operação."),

    // Pagamentos
    BOLETO_INVALIDO(HttpStatus.BAD_REQUEST,
        "Linha digitável inválida. Confira os números."),
    BOLETO_VENCIDO(HttpStatus.UNPROCESSABLE_ENTITY,
        "Este boleto está vencido e não pode ser pago pelo app."),
    BOLETO_JA_PAGO(HttpStatus.CONFLICT,
        "Este boleto já foi pago."),
    TELEFONE_INVALIDO(HttpStatus.BAD_REQUEST,
        "Número de celular inválido. Informe DDD e número."),
    VALOR_RECARGA_INVALIDO(HttpStatus.UNPROCESSABLE_ENTITY,
        "Valor de recarga não disponível para esta operadora."),

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

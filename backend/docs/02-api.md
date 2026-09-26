# 02 — Contrato da API REST

> **Status: especificação.** Nenhum destes endpoints existe. O app iOS consome
> hoje o `MockAccountService`, que devolve `MockData.snapshot()` após 450 ms de
> latência artificial. Este documento descreve a API que substitui esse mock
> implementando `AccountServicing` sobre rede.

Os nomes de campo seguem o domínio do app (`counterparty`, `authCode`, `method`,
`category`, `masked`, `annualYield`) para que o `Codable` do Swift funcione com
o mínimo de mapeamento. Ver [01-dominio.md](01-dominio.md) para as entidades.

---

## 1. Convenções

### 1.1 Base e versionamento

```
https://api.aurora.com.br/v1
```

Versão no caminho. `/v1` é congelado quanto a quebras: campo novo em resposta é
compatível, campo removido ou com tipo alterado exige `/v2`. Enums podem ganhar
valores — **o cliente precisa tolerar valor de enum desconhecido**, caindo num
caso default em vez de falhar o parse. Um `PaymentMethod` novo no servidor não
pode derrubar o extrato de quem está numa versão antiga do app.

Headers obrigatórios em toda requisição:

| Header | Exemplo | Nota |
|---|---|---|
| `Authorization` | `Bearer eyJhbGci...` | Exceto nos endpoints de onboarding e login |
| `X-Device-Id` | `9f2b1c4e-...` | `devices.install_id` |
| `X-App-Version` | `1.4.0 (204)` | |
| `X-Platform` | `ios` | |
| `Accept-Language` | `pt-BR` | Define o idioma das mensagens de erro |
| `X-Request-Id` | UUID v4 | Gerado pelo cliente; volta no `trace_id` do erro |

Headers de resposta relevantes:

| Header | Nota |
|---|---|
| `X-Trace-Id` | Sempre presente. Correlaciona com `audit_logs.trace_id` |
| `Idempotent-Replay` | `true` quando a resposta veio do cache de idempotência |
| `RateLimit-Remaining` | Requisições restantes na janela |
| `Retry-After` | Em `409 REQUISICAO_EM_ANDAMENTO` e `429` |

### 1.2 Autenticação

Bearer JWT no header `Authorization`.

| Token | TTL | Onde vive | Conteúdo |
|---|---|---|---|
| Access | 15 min | Memória do app, nunca em disco | `sub` (user id), `did` (device id), `sid` (session), `scp`, `aal` |
| Refresh | 30 dias | Keychain, `WhenUnlockedThisDeviceOnly` | Opaco, rotativo |
| Step-up | 5 min | Memória | Emitido após prova de PIN/biometria; ver §7 |

Assinatura EdDSA (Ed25519), chaves em HSM/KMS, rotação a cada 90 dias, JWKS em
`/v1/.well-known/jwks.json`.

O claim `aal` (Authentication Assurance Level) governa o que a sessão pode fazer:

| `aal` | Como se obtém | Permite |
|---|---|---|
| `1` | Refresh token válido | Leitura: saldo, extrato, faturas, notificações |
| `2` | PIN ou biometria nesta sessão | Escrita de baixo risco: criar cofrinho, marcar notificação |
| `3` | Step-up token desta operação | Movimentar dinheiro, alterar limite, criar chave Pix |

Um `POST /v1/pix/payments` com `aal < 3` recebe `403 AUTORIZACAO_NECESSARIA`.

Refresh tokens são rotativos: cada uso emite um novo e invalida o anterior.
Reuso de token já consumido é sinal de roubo — revoga toda a família de tokens
daquele device e dispara notificação de segurança.

### 1.3 Idempotência

Todo `POST`, `PUT`, `PATCH` e `DELETE` exige:

```
Idempotency-Key: 7d3f2a10-9c44-4e8b-b1e2-0f5a6c8d1234
```

UUID v4 gerado pelo cliente **por intenção do usuário**, não por tentativa HTTP.
Todas as retentativas do mesmo Pix reusam a mesma chave. No app, cada
`FlowSession` deve gerar a sua ao entrar no passo `.pin`.

Ausência do header → `400 IDEMPOTENCY_KEY_AUSENTE`.
Mesma chave com corpo diferente → `409 IDEMPOTENCY_KEY_REUTILIZADA`.
Mesma chave com mesmo corpo → resposta original, `Idempotent-Replay: true`.
Chave em processamento → `409 REQUISICAO_EM_ANDAMENTO` com `Retry-After: 2`.

Escopo `(user_id, endpoint, key)`, TTL de 24h. Detalhes em
[01-dominio.md §7](01-dominio.md#7-idempotência).

### 1.4 Paginação por cursor

Nunca `offset`/`page`: o extrato recebe transações novas o tempo todo, e offset
duplica ou pula itens. Cursor é opaco (base64 de `sequence` + id), estável, e não
vaza a cardinalidade da tabela.

Requisição: `?limit=50&cursor=eyJzIjoxODQyMDAxLCJpIjoiM2Y..."`
`limit` default 25, máximo 100.

```json
{
  "data": [ /* … */ ],
  "page": {
    "next_cursor": "eyJzIjoxODQxOTUxLCJpIjoiN2E5Yi0uLi4ifQ==",
    "has_more": true
  }
}
```

`next_cursor` ausente ou `null` com `has_more: false` significa fim.
O cursor expira em 15 minutos; usar um expirado devolve `400 CURSOR_INVALIDO`.

### 1.5 Formato de valores

**Sempre inteiro de centavos mais a moeda.** Nunca decimal, nunca string.

```json
{ "amount": 8740, "currency": "BRL" }
```

`8740` é R$ 87,40. Em campos onde a moeda é implícita e invariante (uma lista de
valores do mesmo objeto), a API ainda assim repete `currency` — custa 20 bytes e
elimina ambiguidade.

Valores são **sempre positivos**; o sentido vem de `direction` (`"debit"` /
`"credit"`). Isso difere do app, onde `Transaction.amount` é assinado e
`isCredit` é `amount.isPositive`. Na integração, o `Codable` de `Transaction`
deve montar o `Money` assinado a partir de `amount` + `direction`.

Taxas e percentuais são número decimal JSON com até 6 casas: `"monthly_rate": 0.0249`.
Não são dinheiro, e a precisão de `double` é suficiente para uma taxa — mas o
cálculo derivado dela acontece **no servidor**, em decimal.

### 1.6 Formato de datas

| Tipo | Formato | Exemplo | Uso |
|---|---|---|---|
| Instante | ISO 8601 UTC com `Z` | `"2026-09-26T15:32:10Z"` | `occurred_at`, `created_at`, `settled_at` |
| Data de calendário | `YYYY-MM-DD` | `"2026-10-10"` | `due_date`, `deadline`, `first_due_date` |
| Mês de competência | `YYYY-MM` | `"2026-09"` | `reference_month` |

Nunca offset local na resposta. O app converte para exibição, como já faz.
Filtros de período aceitam `YYYY-MM-DD` e são interpretados em
`America/Sao_Paulo` — `?from=2026-09-01` significa 00:00 de 1º de setembro em
São Paulo, ou seja `2026-09-01T03:00:00Z`.

### 1.7 Limitação de taxa

| Grupo | Limite |
|---|---|
| Leitura autenticada | 120 req/min por usuário |
| Escrita autenticada | 30 req/min por usuário |
| Login / prova de PIN | 10 req/min por device, 5 falhas → bloqueio progressivo |
| Consulta DICT | 20 req/min por usuário (limite do BCB) |
| Onboarding não autenticado | 20 req/hora por IP |

Estouro devolve `429 LIMITE_DE_REQUISICOES` com `Retry-After` em segundos.

---

## 2. Formato de erro

Todo erro, em qualquer endpoint, tem exatamente esta forma:

```json
{
  "error": {
    "code": "SALDO_INSUFICIENTE",
    "message": "Seu saldo é de R$ 1.950,31 e a transferência é de R$ 2.000,00.",
    "field": "amount",
    "trace_id": "01JBQ7X2K9M3N4P5Q6R7S8T9V0",
    "details": {
      "available": 195031,
      "requested": 200000,
      "currency": "BRL"
    }
  }
}
```

| Campo | Obrig. | Nota |
|---|---|---|
| `code` | sim | `SCREAMING_SNAKE_CASE` em português. Estável — é contrato. |
| `message` | sim | Legível, em pt-BR, pronto para exibir. Segunda pessoa, sem jargão, sem código técnico. |
| `field` | não | Caminho JSON do campo problemático: `"amount"`, `"recipient.key"`. |
| `trace_id` | sim | Também no header `X-Trace-Id`. É o que o suporte pede. |
| `details` | não | Dados estruturados para o cliente decidir a UI (ex.: mostrar o saldo disponível). |

Erros de validação de múltiplos campos usam `code: "DADOS_INVALIDOS"` e
`details.fields` como array de `{field, code, message}`.

**O cliente nunca deve parsear `message`.** Decisões de UI vêm de `code` e
`details`. `message` pode mudar de redação a qualquer momento.

### 2.1 Códigos de erro do domínio

**Autenticação e sessão** (`401` / `403`)

| Código | HTTP | Quando |
|---|---|---|
| `NAO_AUTENTICADO` | 401 | Token ausente, malformado ou expirado |
| `SESSAO_EXPIRADA` | 401 | Refresh token expirado — voltar ao login |
| `SESSAO_REVOGADA` | 401 | Sessão encerrada remotamente ou por reuso de refresh |
| `PIN_INCORRETO` | 401 | Prova de PIN inválida. `details.remaining_attempts` |
| `PIN_BLOQUEADO` | 423 | Tentativas esgotadas. `details.locked_until` |
| `PIN_NAO_CADASTRADO` | 409 | Usuário sem PIN — enviar ao fluxo de criação |
| `DESAFIO_EXPIRADO` | 400 | Challenge de PIN passou dos 120 s |
| `DESAFIO_JA_USADO` | 409 | Replay de challenge |
| `AUTORIZACAO_NECESSARIA` | 403 | `aal` insuficiente — pedir PIN ou biometria |
| `DISPOSITIVO_NAO_RECONHECIDO` | 403 | Device fora da lista de confiáveis |
| `DISPOSITIVO_REVOGADO` | 403 | Device bloqueado pelo usuário ou por fraude |
| `BIOMETRIA_NAO_HABILITADA` | 409 | Device sem chave biométrica registrada |
| `CONTA_BLOQUEADA` | 403 | `users.status = BLOCKED` |

**Saldo e limites** (`422`)

| Código | HTTP | Quando |
|---|---|---|
| `SALDO_INSUFICIENTE` | 422 | Débito maior que o disponível. `details.available` |
| `LIMITE_NOTURNO_EXCEDIDO` | 422 | 20h–6h e valor acima do limite. `details.limit`, `details.window` |
| `LIMITE_DIARIO_EXCEDIDO` | 422 | `details.limit`, `details.used`, `details.resets_at` |
| `LIMITE_POR_TRANSACAO_EXCEDIDO` | 422 | |
| `LIMITE_CARTAO_EXCEDIDO` | 422 | Compra acima do limite disponível do cartão |
| `VALOR_INVALIDO` | 422 | Zero, negativo, ou acima do máximo do produto |
| `VALOR_ABAIXO_DO_MINIMO` | 422 | `details.minimum` |
| `COFRINHO_SALDO_INSUFICIENTE` | 422 | Resgate maior que o guardado |
| `POSICAO_INSUFICIENTE` | 422 | Resgate de investimento acima do disponível |

**Pix** (`404` / `422` / `502`)

| Código | HTTP | Quando |
|---|---|---|
| `CHAVE_PIX_NAO_ENCONTRADA` | 404 | DICT não conhece a chave |
| `CHAVE_PIX_INVALIDA` | 422 | Formato incompatível com o tipo |
| `CHAVE_PIX_JA_CADASTRADA` | 409 | Chave pertence a outra conta |
| `LIMITE_CHAVES_PIX_ATINGIDO` | 422 | Máximo de 5 chaves por CPF |
| `CHAVE_PIX_EM_PORTABILIDADE` | 409 | Reivindicação em curso |
| `DESTINATARIO_IGUAL_ORIGEM` | 422 | Pix para a própria conta |
| `INSTITUICAO_INDISPONIVEL` | 502 | PSP destino fora do ar |
| `PIX_NAO_LIQUIDADO` | 409 | Operação exige transação `SETTLED` |
| `DEVOLUCAO_FORA_DO_PRAZO` | 422 | MED só nos 90 dias após a liquidação |
| `DEVOLUCAO_VALOR_EXCEDE_ORIGINAL` | 422 | Soma das devoluções > original |
| `QRCODE_INVALIDO` | 422 | BR Code malformado ou CRC errado |
| `QRCODE_EXPIRADO` | 422 | QR dinâmico vencido |

**Pagamentos** (`404` / `422`)

| Código | HTTP | Quando |
|---|---|---|
| `LINHA_DIGITAVEL_INVALIDA` | 422 | Dígito verificador não confere |
| `BOLETO_NAO_ENCONTRADO` | 404 | Não consta na base CIP |
| `BOLETO_VENCIDO` | 422 | Fora do prazo de pagamento. `details.due_date` |
| `BOLETO_JA_PAGO` | 409 | `details.paid_at` |
| `BOLETO_FORA_DO_HORARIO` | 422 | Boleto acima de R$ 250 mil fora do expediente |
| `BOLETO_VALOR_DIVERGENTE` | 422 | Valor informado ≠ valor do título |
| `OPERADORA_NAO_IDENTIFICADA` | 422 | Recarga: número sem operadora |
| `VALOR_RECARGA_INVALIDO` | 422 | Fora da tabela da operadora. `details.allowed_amounts` |

**Cartões e fatura** (`404` / `409` / `422`)

| Código | HTTP | Quando |
|---|---|---|
| `CARTAO_NAO_ENCONTRADO` | 404 | |
| `CARTAO_BLOQUEADO` | 409 | Operação exige cartão ativo |
| `CARTAO_JA_BLOQUEADO` | 409 | |
| `FATURA_NAO_ENCONTRADA` | 404 | |
| `FATURA_JA_PAGA` | 409 | |
| `FATURA_ABERTA_NAO_PAGAVEL` | 422 | Só se paga fatura fechada |
| `FATURA_NAO_PARCELAVEL` | 422 | Abaixo do mínimo ou já parcelada |
| `LIMITE_SOLICITADO_NEGADO` | 422 | Análise recusou. `details.max_approved` |

**Crédito** (`404` / `409` / `422`)

| Código | HTTP | Quando |
|---|---|---|
| `CREDITO_NAO_APROVADO` | 422 | Análise recusou. `details.reason_code` |
| `SIMULACAO_EXPIRADA` | 409 | Proposta fora das 48h |
| `CONTRATO_NAO_ENCONTRADO` | 404 | |
| `PARCELA_JA_PAGA` | 409 | Invariante I-6 |
| `PARCELA_NAO_ENCONTRADA` | 404 | |
| `PRAZO_INVALIDO` | 422 | Fora de `details.allowed_terms` |

**Genéricos**

| Código | HTTP | Quando |
|---|---|---|
| `DADOS_INVALIDOS` | 400 | Validação de schema. `details.fields` |
| `IDEMPOTENCY_KEY_AUSENTE` | 400 | Escrita sem o header |
| `IDEMPOTENCY_KEY_REUTILIZADA` | 409 | Mesma chave, corpo diferente |
| `REQUISICAO_EM_ANDAMENTO` | 409 | Chave em `IN_PROGRESS`. `Retry-After` |
| `CURSOR_INVALIDO` | 400 | Cursor malformado ou expirado |
| `RECURSO_NAO_ENCONTRADO` | 404 | |
| `CONFLITO_DE_VERSAO` | 409 | `If-Match` não confere |
| `LIMITE_DE_REQUISICOES` | 429 | `Retry-After` |
| `SERVICO_INDISPONIVEL` | 503 | Manutenção ou dependência crítica fora |
| `ERRO_INTERNO` | 500 | `message` genérica; detalhe só no log |

---

## 3. Onboarding e KYC

> **Hoje mockado:** o app não tem onboarding de verdade — `AppPhase.onboarding`
> leva direto à criação de PIN local, e `MockData.snapshot()` já devolve a
> Marina Costa pronta. Todo este grupo é construção nova.

Fluxo: `POST proposals` → `PUT proposals/{id}` (dados) → `POST documents`
(frente, verso) → `POST liveness` → polling de `GET proposals/{id}` até
`APPROVED` → `POST pin` → sessão emitida.

### `POST /v1/onboarding/proposals`

Sem autenticação. Cria a proposta e vincula ao device.

```json
{
  "cpf": "48291733012",
  "birth_date": "1994-03-18",
  "email": "marina.costa@email.com",
  "phone": "+5511998733120",
  "device": {
    "install_id": "9f2b1c4e-7a31-4d0e-9c88-2e5f1a0b3c44",
    "public_key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
    "key_attestation": "o2NmbXRvYXBwbGUtYXBwYXR0ZXN0...",
    "model": "iPhone 15",
    "os_version": "iOS 18.2",
    "app_version": "1.4.0"
  },
  "referral_code": null
}
```

`201`:
```json
{
  "proposal_id": "b3d9f1a2-5c67-4e8a-9b01-2f3c4d5e6a7b",
  "state": "IDENTITY_PENDING",
  "next_step": "document",
  "required_documents": ["RG_FRONT", "RG_BACK"],
  "expires_at": "2026-09-27T15:32:10Z",
  "onboarding_token": "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9..."
}
```

`onboarding_token` (TTL 24h, escopo `onboarding:*`) autentica os próximos passos.

Estados: `IDENTITY_PENDING` → `DOCUMENTS_PENDING` → `LIVENESS_PENDING` →
`UNDER_REVIEW` → `APPROVED` | `REJECTED` | `EXPIRED`.

Erros: `DADOS_INVALIDOS`, `CPF_JA_CADASTRADO` (409), `CPF_IRREGULAR` (422, situação
na Receita), `IDADE_MINIMA_NAO_ATINGIDA` (422).

### `POST /v1/onboarding/proposals/{id}/documents`

`multipart/form-data`: `type` (`RG_FRONT`|`RG_BACK`|`CNH`|`PROOF_OF_ADDRESS`) e
`file` (JPEG/PNG, ≤ 8 MB).

`202`:
```json
{
  "document_id": "d1e2f3a4-...",
  "type": "RG_FRONT",
  "state": "PROCESSING",
  "quality_hints": []
}
```

Quando a análise reprova a imagem, `GET` do documento devolve
`state: "REJECTED"` e `quality_hints: ["BLURRY", "GLARE", "CROPPED"]` — o app
mostra a dica e pede nova foto.

Erros: `ARQUIVO_MUITO_GRANDE` (413), `FORMATO_NAO_SUPORTADO` (415),
`DOCUMENTO_ILEGIVEL` (422), `DOCUMENTO_DIVERGENTE` (422, dados não batem com o CPF).

### `POST /v1/onboarding/proposals/{id}/liveness`

```json
{
  "provider": "unico",
  "session_id": "lv_8f3a2b1c",
  "encrypted_payload": "BASE64..."
}
```

O vídeo/selfie nunca passa pela nossa API: o SDK do provedor sobe direto e nos
devolve um `session_id` que validamos server-to-server. Biometria facial é dado
sensível (LGPD art. 5º II) — quanto menos trafega por nós, melhor.

`202`: `{ "state": "UNDER_REVIEW", "estimated_seconds": 45 }`

Erros: `LIVENESS_FALHOU` (422, `details.reason`: `NO_FACE`, `SPOOF_SUSPECTED`,
`FACE_MISMATCH`), `LIVENESS_TENTATIVAS_ESGOTADAS` (429, máximo 3).

### `GET /v1/onboarding/proposals/{id}`

```json
{
  "proposal_id": "b3d9f1a2-...",
  "state": "APPROVED",
  "next_step": "create_pin",
  "account": {
    "agency": "0001",
    "number": "482917",
    "check_digit": "3",
    "display": "482917-3"
  },
  "initial_limits": {
    "pix_daily": 500000,
    "pix_nightly": 100000,
    "card_credit_limit": 500000,
    "currency": "BRL"
  },
  "rejection": null
}
```

`initial_limits.card_credit_limit` de 500000 centavos = R$ 5.000,00, batendo com
`Card.limit` do mock. `pix_nightly` de R$ 1.000,00 bate com `Settings.nightLimit`.

Rejeitada: `"rejection": { "code": "SCORE_INSUFICIENTE", "message": "...", "retry_after": "2027-03-26" }`.

### `POST /v1/onboarding/proposals/{id}/consents`

```json
{
  "consents": [
    { "type": "TERMS_OF_USE", "document_version": "2026-03-v4", "granted": true },
    { "type": "PRIVACY_POLICY", "document_version": "2026-03-v2", "granted": true },
    { "type": "CREDIT_BUREAU_QUERY", "document_version": "2026-01-v1", "granted": true },
    { "type": "MARKETING", "document_version": "2026-01-v1", "granted": false }
  ]
}
```

`201` devolve cada consentimento com `id`, `granted_at` e `document_hash`.
`TERMS_OF_USE` e `PRIVACY_POLICY` com `granted: false` → `422 CONSENTIMENTO_OBRIGATORIO`.

### `POST /v1/onboarding/proposals/{id}/pin`

Cria o PIN. **O PIN não trafega.** Ver §7.

```json
{
  "verifier": "BASE64_DO_VERIFICADOR",
  "kdf": { "algorithm": "argon2id", "salt": "BASE64_SALT_16B", "t": 3, "m": 65536, "p": 1 },
  "device_signature": "BASE64_ASSINATURA_P256"
}
```

`201`: sessão completa.
```json
{
  "access_token": "eyJhbGciOiJFZERTQSJ9...",
  "refresh_token": "art_7f3a2b1c9d0e4f5a6b7c8d9e0f1a2b3c",
  "token_type": "Bearer",
  "expires_in": 900,
  "aal": 3,
  "user": { "id": "a1b2c3d4-...", "name": "Marina Costa" }
}
```

Erros: `PIN_FRACO` (422 — sequências `123456`, repetições `111111`, data de
nascimento), `PIN_JA_CADASTRADO` (409).

---

## 4. Autenticação

### `POST /v1/auth/challenge`

Sem autenticação. Primeiro passo de qualquer prova de PIN ou biometria.

```json
{ "install_id": "9f2b1c4e-...", "purpose": "LOGIN" }
```

`purpose`: `LOGIN` | `STEP_UP` | `PIN_CHANGE`.

`200`:
```json
{
  "challenge_id": "ch_01JBQ7X2K9M3N4P5Q6R7S8T9V0",
  "nonce": "BASE64_32_BYTES_ALEATORIOS",
  "kdf": { "algorithm": "argon2id", "salt": "BASE64_SALT_16B", "t": 3, "m": 65536, "p": 1 },
  "expires_at": "2026-09-26T15:34:10Z"
}
```

O `kdf.salt` é o mesmo usado na criação do PIN, devolvido para que o device
possa rederivar. Challenge vale 120 s e é consumível uma única vez.

### `POST /v1/auth/login`

Login por device + PIN.

```json
{
  "challenge_id": "ch_01JBQ7X2K9M3N4P5Q6R7S8T9V0",
  "install_id": "9f2b1c4e-...",
  "proof": "BASE64_HMAC_SHA256",
  "device_signature": "BASE64_ASSINATURA_P256_DO_NONCE"
}
```

`200`:
```json
{
  "access_token": "eyJhbGciOiJFZERTQSJ9...",
  "refresh_token": "art_7f3a2b1c9d0e4f5a6b7c8d9e0f1a2b3c",
  "token_type": "Bearer",
  "expires_in": 900,
  "aal": 2,
  "user": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "Marina Costa",
    "initials": "MC"
  },
  "requires_mfa": false
}
```

`aal: 2` — login por PIN autentica, mas movimentar dinheiro ainda exige step-up
por operação (§7).

Device desconhecido devolve `403 DISPOSITIVO_NAO_RECONHECIDO` com
`details.mfa_challenge_id`, e o fluxo passa por `POST /v1/auth/mfa/verify`
(OTP por SMS no telefone cadastrado) antes de emitir tokens.

Erros: `PIN_INCORRETO` (401, `details.remaining_attempts`), `PIN_BLOQUEADO` (423,
`details.locked_until`), `DESAFIO_EXPIRADO`, `DESAFIO_JA_USADO`,
`DISPOSITIVO_REVOGADO`, `CONTA_BLOQUEADA`.

### `POST /v1/auth/biometric`

Login por biometria. A biometria é validada **localmente** pelo `LocalAuthentication`
do iOS; o que prova ao servidor é a assinatura de uma chave guardada na Secure
Enclave com `.biometryCurrentSet` — que o iOS só libera após o Face ID passar.

```json
{
  "challenge_id": "ch_01JBQ7X2K9M3N4P5Q6R7S8T9V0",
  "install_id": "9f2b1c4e-...",
  "biometric_signature": "BASE64_ASSINATURA_P256_DO_NONCE",
  "biometry_type": "faceID"
}
```

Resposta igual à do login por PIN.

Erros: `BIOMETRIA_NAO_HABILITADA` (409), `ASSINATURA_INVALIDA` (401),
`CHAVE_BIOMETRICA_INVALIDADA` (409 — usuário mudou o Face ID cadastrado no
aparelho; a chave da Secure Enclave foi invalidada e é preciso reenrolar com PIN).

> **Hoje mockado:** `KeychainSecurityService.authenticateWithBiometrics` chama o
> `LAContext` de verdade, mas o resultado não prova nada a servidor nenhum —
> não existe chave assimétrica nem assinatura. Falta registrar a chave pública
> da Secure Enclave em `devices.public_key`.

### `POST /v1/auth/biometric/enroll`

Requer `aal: 3`. Registra a chave biométrica do device.

```json
{
  "public_key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
  "attestation": "o2NmbXRvYXBwbGUtYXBwYXR0ZXN0...",
  "biometry_type": "faceID"
}
```

`201`: `{ "enrolled": true, "biometry_type": "faceID" }`

### `POST /v1/auth/refresh`

Sem `Authorization` (o access token já expirou).

```json
{ "refresh_token": "art_7f3a2b1c9d0e4f5a6b7c8d9e0f1a2b3c", "install_id": "9f2b1c4e-..." }
```

`200` devolve novo par. O refresh antigo é invalidado no mesmo instante.
Reuso de refresh consumido → `401 SESSAO_REVOGADA`, revogação de toda a família
de tokens do device e notificação de segurança.

### `POST /v1/auth/logout`

`204`. Revoga a sessão corrente. O device permanece confiável — é logout, não
esquecimento de aparelho.

### `GET /v1/auth/sessions`

```json
{
  "data": [
    {
      "id": "se_3f2a1b0c",
      "device": { "id": "9f2b1c4e-...", "name": "iPhone 15", "model": "iPhone 15", "biometry_type": "faceID" },
      "is_current": true,
      "created_at": "2026-09-26T09:12:44Z",
      "last_seen_at": "2026-09-26T15:31:02Z",
      "location": "São Paulo, SP",
      "ip_masked": "189.45.***.***"
    },
    {
      "id": "se_9d8c7b6a",
      "device": { "id": "1a2b3c4d-...", "name": "iPad de Marina", "model": "iPad Air", "biometry_type": "touchID" },
      "is_current": false,
      "created_at": "2026-09-20T18:02:11Z",
      "last_seen_at": "2026-09-24T21:44:09Z",
      "location": "Campinas, SP",
      "ip_masked": "177.12.***.***"
    }
  ],
  "page": { "next_cursor": null, "has_more": false }
}
```

Alimenta a notificação "Novo acesso reconhecido · iPhone 15 · São Paulo, SP" que
hoje é literal em `AppModel.seedNotifications()`.

### `DELETE /v1/auth/sessions/{id}` e `DELETE /v1/auth/sessions`

Requer `aal: 3`. Revoga uma sessão ou todas exceto a atual. `204`.

### `POST /v1/auth/pin` (alterar PIN)

Requer `aal: 3` obtido com o PIN **atual**. Corpo igual ao de criação.
Invalida todas as sessões exceto a corrente.

---

## 5. Conta

### `GET /v1/account/snapshot`

O endpoint que substitui `MockAccountService.loadAccount()`. Devolve tudo que
`AccountSnapshot` carrega, numa chamada, para que o app abra com uma requisição.

```json
{
  "user": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "Marina Costa",
    "cpf_masked": "482.917.330-12",
    "email": "marina.costa@email.com",
    "phone": "(11) 99873-3120",
    "agency": "0001",
    "account": "482917-3"
  },
  "balance": {
    "available": 195031,
    "settled": 195031,
    "blocked": 0,
    "currency": "BRL",
    "as_of": "2026-09-26T15:32:10Z"
  },
  "card": {
    "id": "cd_7f3a2b1c",
    "kind": "fisico",
    "brand": "MASTERCARD",
    "masked_number": "•••• •••• •••• 4821",
    "is_blocked": false,
    "limit": 500000,
    "available_limit": 407430,
    "cashback": 3820,
    "invoice_due": "2026-10-10",
    "invoice_amount": 92570,
    "currency": "BRL"
  },
  "holdings": [
    { "product_id": "cdb",   "invested": 780000, "current": 820000, "currency": "BRL" },
    { "product_id": "selic", "invested": 515000, "current": 535000, "currency": "BRL" },
    { "product_id": "lci",   "invested": 290000, "current": 300000, "currency": "BRL" },
    { "product_id": "fii",   "invested": 150000, "current": 148000, "currency": "BRL" }
  ],
  "goals": [
    {
      "id": "go_1a2b3c4d",
      "name": "Viagem para o Chile",
      "saved": 320000,
      "target": 800000,
      "symbol": "airplane",
      "deadline": "2027-05-26",
      "currency": "BRL"
    },
    {
      "id": "go_5e6f7a8b",
      "name": "Reserva de emergência",
      "saved": 940000,
      "target": 1200000,
      "symbol": "shield.fill",
      "deadline": null,
      "currency": "BRL"
    },
    {
      "id": "go_9c0d1e2f",
      "name": "Notebook novo",
      "saved": 115000,
      "target": 650000,
      "symbol": "laptopcomputer",
      "deadline": "2027-02-26",
      "currency": "BRL"
    }
  ],
  "loans": [],
  "pix_keys": [
    { "id": "pk_3a4b5c6d", "kind": "cpf",     "masked": "***.917.330-**", "state": "ACTIVE" },
    { "id": "pk_7e8f9a0b", "kind": "celular", "masked": "(11) 9****-3120", "state": "ACTIVE" }
  ],
  "contacts": [
    { "id": "ct_1122aabb", "name": "Ana Luiza Prado", "key": "ana.prado@email.com", "key_kind": "email",   "bank": "Banco Horizonte", "last_used_at": "2026-09-24T14:11:03Z" },
    { "id": "ct_3344ccdd", "name": "João Pedro Lima", "key": "(11) 98820-4471",     "key_kind": "celular", "bank": "Banco Aurora",    "last_used_at": "2026-09-26T12:02:55Z" },
    { "id": "ct_5566eeff", "name": "Bruna Takeda",    "key": "bruna@takeda.dev",    "key_kind": "email",   "bank": "Banco Horizonte", "last_used_at": "2026-08-29T09:30:12Z" },
    { "id": "ct_7788aabb", "name": "Rafael Souza",    "key": "123.456.789-10",      "key_kind": "cpf",     "bank": "Caixa Vermelha",  "last_used_at": null }
  ],
  "monthly_budget": 400000,
  "credit_score": 742,
  "settings": {
    "biometrics_enabled": true,
    "hide_balance_on_open": false,
    "transaction_alerts": true,
    "night_limit_enabled": true,
    "night_limit": 100000
  },
  "unread_notifications": 2,
  "server_time": "2026-09-26T15:32:10Z"
}
```

Diferenças a resolver no app:

- Não há `opening_balance` nem lista de transações: o snapshot traz o saldo
  pronto e o extrato vem paginado. `Ledger` precisa aceitar ser inicializado
  com um saldo já calculado.
- `Card` não traz `number`, `cvv` nem `expiry` — só `masked_number` (§9.3).
- `Holding` chega com `product_id`, não com `id` sendo o produto. O catálogo vem
  de `GET /v1/investments/products`, não do array estático `InvestmentProduct.all`.
- `invoice_amount` vem pronto, substituindo `Ledger.creditInvoice`.
- `server_time` permite o app detectar relógio adiantado e usar o do servidor
  nas regras de horário.

Suporta `ETag` / `If-None-Match` → `304` quando nada mudou.

### `GET /v1/account/balance`

Consulta leve para pull-to-refresh.

```json
{
  "available": 195031,
  "settled": 195031,
  "blocked": 0,
  "currency": "BRL",
  "as_of": "2026-09-26T15:32:10Z"
}
```

`blocked` é o valor de débitos `AUTHORIZED` ainda não liquidados —
`available = settled − blocked + créditos_pendentes_confirmados`.

### `PATCH /v1/account/settings`

Requer `aal: 2`. Corpo parcial com os campos de `Settings`.

```json
{ "night_limit_enabled": true, "night_limit": 150000 }
```

`200` devolve o objeto completo. Aumento de `night_limit` acima do teto do banco
é recusado com `LIMITE_SOLICITADO_NEGADO` e `details.max_allowed`; aumentos de
limite Pix têm carência regulatória de 24h, informada em `details.effective_at`.

### `GET /v1/account/spending?from=&to=`

Serve o gráfico de gastos (`Ledger.spending`) sem baixar o extrato inteiro.

```json
{
  "period": { "from": "2026-09-01", "to": "2026-09-30" },
  "total_spending": 92570,
  "monthly_budget": 400000,
  "budget_remaining": 307430,
  "currency": "BRL",
  "categories": [
    { "category": "mercado",      "total": 40020, "transaction_count": 3 },
    { "category": "restaurantes", "total": 26340, "transaction_count": 4 },
    { "category": "transporte",   "total": 22910, "transaction_count": 3 },
    { "category": "moradia",      "total": 12990, "transaction_count": 1 },
    { "category": "saude",        "total": 11900, "transaction_count": 1 }
  ]
}
```

Só categorias com `isSpending = true`, ordenadas por total decrescente. O `ratio`
para a largura da barra continua sendo cálculo de apresentação no app.

---

## 6. Extrato

### `GET /v1/transactions`

| Parâmetro | Tipo | Nota |
|---|---|---|
| `from`, `to` | `YYYY-MM-DD` | Interpretados em `America/Sao_Paulo` |
| `direction` | `debit` \| `credit` | |
| `category` | csv de `Category` | `?category=mercado,restaurantes` |
| `method` | csv de `PaymentMethod` | |
| `state` | csv de estados | Default: todos menos `FAILED` |
| `min_amount`, `max_amount` | inteiro de centavos | |
| `q` | string | Busca em `title` e `counterparty`, full-text português |
| `limit`, `cursor` | | §1.4 |

```json
{
  "data": [
    {
      "id": "tx_0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0",
      "occurred_at": "2026-09-26T12:02:55Z",
      "effective_date": "2026-09-26",
      "title": "Pix recebido",
      "counterparty": "João Pedro Lima",
      "counterparty_document": "***.820.447-**",
      "counterparty_bank": "Banco Aurora",
      "amount": 15000,
      "currency": "BRL",
      "direction": "credit",
      "category": "transferencia",
      "method": "pix",
      "state": "SETTLED",
      "auth_code": "E18236120202609261202A5B4C3D2E1F",
      "note": null
    },
    {
      "id": "tx_1a2b3c4d-5e6f-7081-9293-a4b5c6d7e8f9",
      "occurred_at": "2026-09-26T15:05:12Z",
      "effective_date": "2026-09-26",
      "title": "Mercado Pão Fresco",
      "counterparty": "Compra no crédito",
      "counterparty_document": null,
      "counterparty_bank": null,
      "amount": 8740,
      "currency": "BRL",
      "direction": "debit",
      "category": "mercado",
      "method": "credito",
      "state": "AUTHORIZED",
      "auth_code": "E18236120202609261505F9E8D7C6B5A",
      "note": null
    }
  ],
  "page": { "next_cursor": "eyJzIjoxODQxOTUxLCJpIjoiMWEyYiJ9", "has_more": true },
  "summary": { "credits": 15000, "debits": 8740, "currency": "BRL" }
}
```

Ordenação: `occurred_at DESC, sequence DESC`. O agrupamento por dia
(`TransactionGroup`) continua no cliente, usando `effective_date`.

Note `amount` sempre positivo mais `direction` — diferente de `Transaction.amount`
assinado no Swift. O `state: "AUTHORIZED"` da compra no crédito é informação que
o app hoje não tem e precisa exibir como "processando".

### `GET /v1/transactions/{id}`

Tudo do resumo, mais o detalhe do comprovante:

```json
{
  "id": "tx_0f1e2d3c-...",
  "occurred_at": "2026-09-26T12:02:55Z",
  "settled_at": "2026-09-26T12:02:57Z",
  "title": "Pix recebido",
  "counterparty": "João Pedro Lima",
  "amount": 15000,
  "currency": "BRL",
  "direction": "credit",
  "category": "transferencia",
  "method": "pix",
  "state": "SETTLED",
  "auth_code": "E18236120202609261202A5B4C3D2E1F",
  "receipt": {
    "payer":    { "name": "João Pedro Lima", "document": "***.820.447-**", "bank": "Banco Aurora",     "ispb": "00000000", "agency": "0001", "account": "112233-4" },
    "receiver": { "name": "Marina Costa",    "document": "***.917.330-**", "bank": "Banco Aurora",     "ispb": "00000000", "agency": "0001", "account": "482917-3" },
    "end_to_end_id": "E18236120202609261202A5B4C3D2E1F",
    "pdf_url": "https://api.aurora.com.br/v1/transactions/tx_0f1e2d3c-.../receipt.pdf?token=..."
  },
  "entries": [
    { "account": "CHECKING",   "direction": "credit", "amount": 15000 },
    { "account": "SETTLEMENT", "direction": "debit",  "amount": 15000 }
  ],
  "reversal": null,
  "can_be_refunded": true,
  "refund_deadline": "2026-12-25"
}
```

`entries` expõe o double-entry — útil para suporte e conferência. `pdf_url` é
assinada e vale 5 minutos.

Erros: `RECURSO_NAO_ENCONTRADO`.

### `POST /v1/transactions/export`

```json
{
  "format": "ofx",
  "from": "2026-09-01",
  "to": "2026-09-30",
  "filters": { "category": ["mercado", "restaurantes"] }
}
```

`format`: `csv` | `pdf` | `ofx`. Assíncrono — arquivos de anos inteiros não cabem
num timeout de request.

`202`:
```json
{
  "export_id": "ex_5a6b7c8d",
  "state": "PROCESSING",
  "estimated_seconds": 12,
  "poll_url": "/v1/transactions/export/ex_5a6b7c8d"
}
```

`GET /v1/transactions/export/{id}` quando pronto:
```json
{
  "export_id": "ex_5a6b7c8d",
  "state": "READY",
  "format": "ofx",
  "download_url": "https://files.aurora.com.br/exports/ex_5a6b7c8d.ofx?token=...",
  "expires_at": "2026-09-26T16:32:10Z",
  "size_bytes": 48210,
  "transaction_count": 25
}
```

URL assinada, válida por 1 hora, uso único. O download é logado em `audit_logs`.

Erros: `PERIODO_MUITO_LONGO` (422, máximo 5 anos), `FORMATO_NAO_SUPORTADO`.

---

## 7. Autorização por PIN

> Esta seção é o coração da segurança transacional. Vale para todo endpoint
> marcado com `aal: 3`.

### 7.1 O PIN nunca trafega em claro

Não existe `{"pin": "1234"}` em lugar nenhum desta API. Três razões:

1. **TLS não é suficiente.** Um proxy corporativo, um certificado comprometido
   ou um log de aplicação mal configurado expõem o corpo da requisição. PIN em
   log de acesso é incidente de segurança grave e acontece o tempo todo.
2. **O servidor não deve poder conhecer o PIN**, nem transitoriamente em memória.
   Se o servidor nunca vê o PIN, um comprometimento do servidor não o revela.
3. **Replay.** Um PIN em claro capturado uma vez serve para sempre. Uma prova
   ligada a um nonce serve uma vez só.

### 7.2 Desenho: challenge do servidor + prova derivada no device

```
App                                              API
 │                                                │
 │  POST /v1/auth/challenge {purpose: STEP_UP}    │
 │───────────────────────────────────────────────>│
 │                                                │  gera nonce (32B), grava
 │                                                │  challenge com TTL 120s
 │  {challenge_id, nonce, kdf{salt,t,m,p}}        │
 │<───────────────────────────────────────────────│
 │                                                │
 │  usuário digita o PIN no teclado do app        │
 │  k = Argon2id(pin, salt, t, m, p)  ← no device │
 │  proof = HMAC-SHA256(k, nonce ‖ challenge_id   │
 │            ‖ install_id ‖ operation_hash)      │
 │  sig = ECDSA-P256(device_private_key, proof)   │
 │  ⌫ zera o PIN da memória                        │
 │                                                │
 │  POST /v1/auth/step-up {challenge_id, proof,   │
 │                          device_signature}     │
 │───────────────────────────────────────────────>│
 │                                                │  recomputa a prova esperada
 │                                                │  a partir do verifier guardado,
 │                                                │  compara em tempo constante,
 │                                                │  consome o challenge
 │  {authorization_token, expires_in: 300}        │
 │<───────────────────────────────────────────────│
 │                                                │
 │  POST /v1/pix/payments                         │
 │    Authorization: Bearer <access>              │
 │    X-Authorization-Token: <authorization_token>│
 │    Idempotency-Key: <uuid>                     │
 │───────────────────────────────────────────────>│
```

O que o servidor guarda em `pin_credentials` é o **verificador**: `Argon2id` do
PIN com o salt do usuário, mais um segundo hash server-side com pepper em KMS.
Do verificador não se recupera o PIN, e sem o PIN não se produz a prova.

`operation_hash` = SHA-256 do corpo canonicalizado da operação que virá. Isso
amarra a autorização àquela operação específica: um token obtido para um Pix de
R$ 60 para a Ana não autoriza um Pix de R$ 6.000 para outra pessoa, mesmo dentro
dos 5 minutos de validade. É a defesa contra um app comprometido reaproveitar
uma autorização legítima.

### 7.3 `POST /v1/auth/step-up`

```json
{
  "challenge_id": "ch_01JBQ7X2K9M3N4P5Q6R7S8T9V0",
  "install_id": "9f2b1c4e-...",
  "proof": "BASE64_HMAC_SHA256",
  "device_signature": "BASE64_ECDSA_P256",
  "operation_hash": "BASE64_SHA256_DO_CORPO"
}
```

`200`:
```json
{
  "authorization_token": "aut_9f8e7d6c5b4a39281706f5e4d3c2b1a0",
  "expires_in": 300,
  "aal": 3,
  "scope": ["pix.send"],
  "operation_hash": "BASE64_SHA256_DO_CORPO"
}
```

O token é **de uso único**. Consumido na primeira operação bem-sucedida. Se a
operação falhar por erro de negócio (`SALDO_INSUFICIENTE`), o token continua
válido para uma retentativa — falha de negócio não é falha de autorização.

Biometria substitui o PIN nesta etapa: `POST /v1/auth/step-up/biometric` com
`biometric_signature` no lugar de `proof`. O `operation_hash` continua obrigatório.

### 7.4 Quando o step-up é exigido

| Operação | Exige? |
|---|---|
| Consultar saldo, extrato, fatura, notificações | Não (`aal: 1`) |
| Criar/editar cofrinho, marcar notificação lida, salvar contato | `aal: 2` |
| Qualquer movimentação de dinheiro | Sim (`aal: 3`) |
| Criar/excluir chave Pix, alterar limites, bloquear cartão | Sim |
| Alterar PIN, revogar sessões, registrar biometria | Sim |

Movimentações abaixo de R$ 200,00 para um contato já usado nos últimos 90 dias
podem dispensar o step-up dentro de 5 minutos de um anterior — política
configurável, controlada pelo servidor, jamais pelo app.

> **Hoje mockado, e é a maior lacuna de segurança do app:** o passo `.pin` do
> `FlowSession` chama `security.verifyPIN()` localmente e, se der verdadeiro,
> executa `commit()` mutando o `AppModel`. A validação é 100% cliente: quem
> tiver o binário modificado pula o PIN inteiro. Além disso, `hashed()` usa
> FNV-1a com sal fixo — 64 bits sobre um espaço de 10⁴ combinações, quebrável
> instantaneamente. Ao integrar, `verifyPIN` deixa de decidir e passa a apenas
> derivar a prova; quem decide é o servidor.

---

## 8. Pix

### 8.1 Chaves

#### `GET /v1/pix/keys`

```json
{
  "data": [
    { "id": "pk_3a4b5c6d", "kind": "cpf",       "masked": "***.917.330-**", "state": "ACTIVE", "created_at": "2025-01-14T10:22:00Z" },
    { "id": "pk_7e8f9a0b", "kind": "celular",   "masked": "(11) 9****-3120", "state": "ACTIVE", "created_at": "2025-01-14T10:23:11Z" }
  ],
  "limits": { "max_keys": 5, "used": 2 }
}
```

O valor completo da chave **nunca** vem na listagem — só `masked`, exatamente
como `PixKey.masked` no Swift. Para copiar a chave, `GET /v1/pix/keys/{id}/reveal`
com `aal: 3`, que devolve o valor e registra em `audit_logs`.

#### `POST /v1/pix/keys`

Requer `aal: 3`.

```json
{ "kind": "aleatoria" }
```

Para `cpf`, `celular` e `email` o valor é o do cadastro e não é informado no
corpo — evita que o app tente registrar chave de terceiro. `202` porque o DICT
é assíncrono:

```json
{
  "id": "pk_1c2d3e4f",
  "kind": "aleatoria",
  "value": "e1f2a3b4-c5d6-7890-abcd-ef1234567890",
  "masked": "e1f2****-****-****-****-********7890",
  "state": "PENDING_CLAIM",
  "estimated_seconds": 5
}
```

A chave aleatória é o único caso em que `value` vem na criação — é a única chance
de o usuário vê-la, e ela não é sigilosa por natureza.

Erros: `LIMITE_CHAVES_PIX_ATINGIDO` (422), `CHAVE_PIX_JA_CADASTRADA` (409, com
`details.claim_available: true` quando dá para reivindicar portabilidade),
`CONTATO_NAO_VERIFICADO` (422, e-mail ou telefone sem verificação).

> **Hoje mockado:** `AppModel.addRandomPixKey()` faz `UUID().uuidString` e
> adiciona ao array, sem DICT, sem limite de 5 e com `masked` igual ao UUID
> inteiro — ou seja, sem máscara nenhuma.

#### `DELETE /v1/pix/keys/{id}`

Requer `aal: 3`. `202`, com `state: "DELETING"` até o DICT confirmar.
Erro: `CHAVE_PIX_EM_PORTABILIDADE` (409).

#### `POST /v1/pix/keys/{id}/portability`

Reivindica chave registrada em outra instituição. `202` com `claim_id` e
`resolution_deadline` (7 dias). Não implementado no app.

### 8.2 Consultar chave (DICT)

#### `GET /v1/pix/dict?key=ana.prado@email.com`

Resolve o destinatário antes de enviar. Passo `.recipient` do `PixFlow`.

```json
{
  "key": "ana.prado@email.com",
  "key_kind": "email",
  "holder": {
    "name": "Ana Luiza Prado",
    "trade_name": null,
    "document": "***.456.789-**",
    "document_kind": "CPF"
  },
  "institution": { "name": "Banco Horizonte", "ispb": "20855875" },
  "account": { "kind": "CACC", "agency": "0001", "number": "556677-8" },
  "end_to_end_id_hint": "E20855875202609261532A1B2C3D4E5F",
  "is_own_account": false,
  "fraud_markers": { "key_created_recently": false, "reported_count": 0 },
  "cached_until": "2026-09-26T15:37:10Z"
}
```

`holder.name` é o que preenche `Contact.name`, `institution.name` preenche
`Contact.bank`. O app hoje usa `"Banco Horizonte"` como default hardcoded no
struct `Contact` — isso vem daqui.

`fraud_markers` permite ao app avisar "esta chave foi criada há 2 dias" antes de
uma transferência de valor alto. Não existe no app.

Consulta ao DICT é rate-limited e auditada pelo BCB — cache de 5 minutos por
`(usuário, chave)`, e consulta em massa é bloqueada.

Erros: `CHAVE_PIX_NAO_ENCONTRADA` (404), `CHAVE_PIX_INVALIDA` (422),
`LIMITE_DE_REQUISICOES` (429), `INSTITUICAO_INDISPONIVEL` (502).

### 8.3 Enviar Pix

#### `POST /v1/pix/payments`

Requer `aal: 3` + `Idempotency-Key`. É o `PixFlow.commit()`.

```json
{
  "key": "ana.prado@email.com",
  "amount": 6000,
  "currency": "BRL",
  "note": "Almoço de sexta",
  "category": "transferencia",
  "save_contact": true,
  "scheduled_for": null
}
```

Alternativa a `key`: `"recipient": { "ispb": "20855875", "agency": "0001", "number": "556677-8", "document": "45678912300", "kind": "CACC" }` para envio por dados bancários.

`201`:
```json
{
  "transaction": {
    "id": "tx_8a7b6c5d-4e3f-2109-8765-4321fedcba09",
    "occurred_at": "2026-09-26T15:32:10Z",
    "title": "Pix enviado",
    "counterparty": "Ana Luiza Prado",
    "amount": 6000,
    "currency": "BRL",
    "direction": "debit",
    "category": "transferencia",
    "method": "pix",
    "state": "AUTHORIZED",
    "auth_code": "E18236120202609261532A1B2C3D4E5F"
  },
  "balance_after": { "available": 189031, "currency": "BRL" },
  "contact": { "id": "ct_1122aabb", "name": "Ana Luiza Prado", "key": "ana.prado@email.com", "bank": "Banco Horizonte" },
  "receipt_url": "https://api.aurora.com.br/v1/transactions/tx_8a7b6c5d-.../receipt.pdf?token=..."
}
```

`state: "AUTHORIZED"` e não `SETTLED`: a liquidação no SPI é assíncrona e chega
por webhook em segundos. O app deve mostrar o comprovante já, marcado como
"processando", e atualizar quando o push de liquidação chegar.

`contact` volta preenchido quando `save_contact: true` — é o que alimenta
`AppModel.rememberContact()`.

Erros: `SALDO_INSUFICIENTE`, `LIMITE_NOTURNO_EXCEDIDO`, `LIMITE_DIARIO_EXCEDIDO`,
`LIMITE_POR_TRANSACAO_EXCEDIDO`, `CHAVE_PIX_NAO_ENCONTRADA`,
`DESTINATARIO_IGUAL_ORIGEM`, `INSTITUICAO_INDISPONIVEL`, `AUTORIZACAO_NECESSARIA`,
`CONTA_BLOQUEADA`, `OPERACAO_BLOQUEADA_ANTIFRAUDE` (422, `details.contact_support: true`).

`LIMITE_NOTURNO_EXCEDIDO` com detalhe:
```json
{
  "error": {
    "code": "LIMITE_NOTURNO_EXCEDIDO",
    "message": "Entre 20h e 6h o limite por transferência é de R$ 1.000,00. Programe para depois das 6h ou solicite aumento de limite.",
    "field": "amount",
    "trace_id": "01JBQ7X2K9M3N4P5Q6R7S8T9V0",
    "details": {
      "limit": 100000,
      "requested": 250000,
      "currency": "BRL",
      "window": { "starts_at": "20:00", "ends_at": "06:00", "timezone": "America/Sao_Paulo" },
      "next_available_at": "2026-09-27T09:00:00Z"
    }
  }
}
```

A janela é avaliada em `America/Sao_Paulo`, não no fuso do device —
`FlowContext.isNight()` usa `Calendar.current`, o que permitiria burlar a regra
mudando o relógio do aparelho.

### 8.4 Pix agendado

#### `POST /v1/pix/scheduled`

Mesmo corpo do envio, com `scheduled_for: "2026-10-05"`. Corresponde a
`PixFlow.scheduledFor`.

`201`:
```json
{
  "id": "sch_2b3c4d5e",
  "state": "SCHEDULED",
  "scheduled_for": "2026-10-05",
  "amount": 6000,
  "currency": "BRL",
  "recipient": { "name": "Ana Luiza Prado", "key": "ana.prado@email.com", "bank": "Banco Horizonte" },
  "recurrence": null,
  "created_at": "2026-09-26T15:32:10Z"
}
```

`recurrence` opcional: `{ "frequency": "MONTHLY", "day": 5, "until": "2027-10-05", "occurrences": null }`.

O saldo **não** é reservado no agendamento — é validado na data. Se faltar, a
transação vai a `FAILED` com `SALDO_INSUFICIENTE` e gera notificação.

`GET /v1/pix/scheduled` lista; `DELETE /v1/pix/scheduled/{id}` cancela (`aal: 3`,
até as 23h59 do dia anterior).

Erros: `DATA_INVALIDA` (422, passado ou além de 2 anos), `AGENDAMENTO_NAO_CANCELAVEL` (409).

### 8.5 Cobrança (QR Code)

#### `POST /v1/pix/charges`

```json
{
  "kind": "dynamic",
  "amount": 15000,
  "currency": "BRL",
  "description": "Rateio do jantar",
  "expires_in": 3600,
  "payer": { "name": "João Pedro Lima", "document": "88204471000" },
  "key_id": "pk_3a4b5c6d"
}
```

`kind`: `static` (sem valor nem validade, reutilizável) ou `dynamic`.

`201`:
```json
{
  "id": "chg_6d7e8f9a",
  "kind": "dynamic",
  "state": "ACTIVE",
  "amount": 15000,
  "currency": "BRL",
  "br_code": "00020126580014br.gov.bcb.pix0136e1f2a3b4-c5d6-7890-abcd-ef12345678900217Rateio do jantar5204000053039865406150.005802BR5912Marina Costa6009Sao Paulo62070503***63042A1B",
  "qr_code_image_url": "https://api.aurora.com.br/v1/pix/charges/chg_6d7e8f9a/qr.png",
  "copy_paste": "00020126580014br.gov.bcb.pix...",
  "expires_at": "2026-09-26T16:32:10Z",
  "paid_transaction_id": null
}
```

`br_code` é o payload EMV completo, com CRC16 calculado pelo servidor.
`GET /v1/pix/charges/{id}` acompanha; quando pago, `state: "PAID"` e
`paid_transaction_id` preenchido.

#### `POST /v1/pix/qr/decode`

Lê um QR de terceiro antes de pagar.

```json
{ "br_code": "00020126580014br.gov.bcb.pix..." }
```

```json
{
  "kind": "dynamic",
  "amount": 15000,
  "amount_is_editable": false,
  "currency": "BRL",
  "description": "Rateio do jantar",
  "merchant": { "name": "João Pedro Lima", "city": "São Paulo", "document": "***.204.471-**" },
  "institution": { "name": "Banco Aurora", "ispb": "00000000" },
  "expires_at": "2026-09-26T16:32:10Z",
  "txid": "RATEIO202609260001"
}
```

Erros: `QRCODE_INVALIDO` (422, CRC errado), `QRCODE_EXPIRADO` (422),
`QRCODE_JA_PAGO` (409).

Pagamento do QR usa `POST /v1/pix/payments` com `"br_code": "..."` no lugar de `key`.

### 8.6 Devolução (MED)

#### `POST /v1/pix/payments/{id}/refunds`

Requer `aal: 3`.

```json
{
  "amount": 15000,
  "currency": "BRL",
  "reason": "MD06",
  "description": "Valor recebido por engano"
}
```

`reason`: `MD06` (devolução solicitada pelo pagador), `BE08` (fraude),
`FR01` (conta do recebedor em análise), `SL02` (erro operacional).

`202`:
```json
{
  "refund_id": "rf_4e5f6a7b",
  "state": "PROCESSING",
  "amount": 15000,
  "currency": "BRL",
  "original_transaction_id": "tx_0f1e2d3c-...",
  "return_end_to_end_id": "D18236120202609261615A1B2C3D4E5F",
  "deadline": "2026-09-27T15:32:10Z"
}
```

Prazo de solicitação: 90 dias da liquidação. Devolução parcial é permitida; a
soma não pode ultrapassar o original (`DEVOLUCAO_VALOR_EXCEDE_ORIGINAL`).

Quando o MED é aberto pelo **pagador** contra um Pix que a Marina recebeu, o
valor é bloqueado na conta dela (aparece em `balance.blocked`) e uma notificação
`security` é gerada. Nada disso existe no app.

Erros: `PIX_NAO_LIQUIDADO` (409), `DEVOLUCAO_FORA_DO_PRAZO` (422),
`DEVOLUCAO_VALOR_EXCEDE_ORIGINAL` (422), `SALDO_INSUFICIENTE`.

### 8.7 Limites

#### `GET /v1/pix/limits`

```json
{
  "limits": [
    { "scope": "TRANSACTION_DAY",   "limit": 500000,  "used": 6000,  "remaining": 494000, "resets_at": "2026-09-27T03:00:00Z" },
    { "scope": "TRANSACTION_NIGHT", "limit": 100000,  "used": 0,     "remaining": 100000, "resets_at": "2026-09-27T09:00:00Z" },
    { "scope": "MONTHLY",           "limit": 5000000, "used": 128740, "remaining": 4871260, "resets_at": "2026-10-01T03:00:00Z" },
    { "scope": "NEW_CONTACT",       "limit": 50000,   "used": 0,     "remaining": 50000,  "resets_at": null }
  ],
  "night_window": { "starts_at": "20:00", "ends_at": "06:00", "timezone": "America/Sao_Paulo" },
  "currency": "BRL"
}
```

`NEW_CONTACT` é limite reduzido para destinatário nunca usado — controle
antifraude que o app não tem.

#### `PATCH /v1/pix/limits`

Requer `aal: 3`.

```json
{ "scope": "TRANSACTION_NIGHT", "limit": 200000 }
```

Redução vale na hora. **Aumento tem carência de 24h**, por exigência da
Resolução BCB 142 — o objetivo é impedir que um golpista que acabou de assumir
a conta eleve o limite e esvazie tudo.

```json
{
  "scope": "TRANSACTION_NIGHT",
  "current_limit": 100000,
  "requested_limit": 200000,
  "effective_at": "2026-09-27T15:32:10Z",
  "state": "PENDING_COOLDOWN"
}
```

O toggle `Settings.nightLimitEnabled` do app não pode desligar o controle: ele
ajusta o valor dentro de um teto do banco. Desligar completamente não é opção
que o servidor ofereça.

---

## 9. Pagamentos

### 9.1 Consultar boleto

#### `GET /v1/payments/barcode?code=34191790010104351004791020150008291070026000`

Aceita linha digitável (47/48 dígitos) ou código de barras (44). Passo
`.recipient` do `BoletoFlow`.

```json
{
  "barcode": "34191790010104351004791020150008291070026000",
  "digitable_line": "34191.79001 01043.510047 91020.150008 2 91070026000",
  "kind": "BANK_SLIP",
  "payee": { "name": "Enel Distribuição São Paulo", "document": "61.695.227/0001-93", "trade_name": "Enel SP" },
  "payer": { "name": "MARINA COSTA", "document": "***.917.330-**" },
  "amount": 18740,
  "original_amount": 18740,
  "discount": 0,
  "interest": 0,
  "fine": 0,
  "currency": "BRL",
  "due_date": "2026-10-02",
  "payment_deadline": "2026-10-02T21:00:00Z",
  "allows_partial_payment": false,
  "amount_is_editable": false,
  "suggested_category": "moradia",
  "state": "PAYABLE"
}
```

`kind`: `BANK_SLIP` (título bancário) ou `UTILITY` (convênio — água, luz, tributo).
`suggested_category` alimenta `BoletoFlow.category` — no app isso vem de
`MockData.boleto()`, que escolhe entre quatro presets pelo hash do código.

Boleto vencido que ainda aceita pagamento vem com `interest` e `fine`
preenchidos e `amount > original_amount`. Boleto fora do prazo:

```json
{
  "error": {
    "code": "BOLETO_VENCIDO",
    "message": "Este boleto venceu em 12/09/2026 e não pode mais ser pago pelo app. Peça uma segunda via ao beneficiário.",
    "field": "code",
    "trace_id": "01JBQ7X2K9M3N4P5Q6R7S8T9V0",
    "details": { "due_date": "2026-09-12", "payee": "Enel Distribuição São Paulo", "allows_reissue": true }
  }
}
```

Erros: `LINHA_DIGITAVEL_INVALIDA` (422, DV errado), `BOLETO_NAO_ENCONTRADO` (404),
`BOLETO_VENCIDO` (422), `BOLETO_JA_PAGO` (409, `details.paid_at`),
`BOLETO_FORA_DO_HORARIO` (422, acima de R$ 250 mil fora do expediente).

> **Hoje mockado:** `MockData.boleto(for:)` sorteia entre Enel, Sabesp, NetVia e
> Imobiliária Vega usando `abs(digits.hashValue) % 4`, e inventa o vencimento
> somando dias a `.now`. Nenhum dígito verificador é conferido.

### 9.2 Pagar boleto

#### `POST /v1/payments/barcode`

Requer `aal: 3` + `Idempotency-Key`. É o `BoletoFlow.commit()`.

```json
{
  "barcode": "34191790010104351004791020150008291070026000",
  "amount": 18740,
  "currency": "BRL",
  "category": "moradia",
  "scheduled_for": null,
  "save_as_favorite": false
}
```

`amount` é obrigatório e é conferido contra o título: divergência devolve
`BOLETO_VALOR_DIVERGENTE`. Isso impede que o app pague um valor diferente do que
mostrou na tela de confirmação.

`201`:
```json
{
  "transaction": {
    "id": "tx_3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f",
    "occurred_at": "2026-09-26T15:32:10Z",
    "title": "Pagamento de boleto",
    "counterparty": "Enel Distribuição São Paulo",
    "amount": 18740,
    "currency": "BRL",
    "direction": "debit",
    "category": "moradia",
    "method": "boleto",
    "state": "AUTHORIZED",
    "auth_code": "E18236120202609261532B2C3D4E5F6A"
  },
  "balance_after": { "available": 176291, "currency": "BRL" },
  "settlement_forecast": "2026-09-26T21:00:00Z",
  "receipt_url": "https://api.aurora.com.br/v1/transactions/tx_3c4d5e6f-.../receipt.pdf?token=..."
}
```

`AUTHORIZED`, não `SETTLED`: a confirmação vem no arquivo de retorno da CIP, o
que pode levar até D+1. O app trata como instantâneo hoje.

Erros: todos os de consulta, mais `SALDO_INSUFICIENTE`, `LIMITE_DIARIO_EXCEDIDO`,
`BOLETO_VALOR_DIVERGENTE` (422).

### 9.3 Recarga de celular

#### `GET /v1/payments/topup/carriers?phone=%2B5511998733120`

```json
{
  "phone": "+5511998733120",
  "carrier": { "id": "vivo", "name": "Vivo", "logo_url": "https://cdn.aurora.com.br/carriers/vivo.png" },
  "portability_checked": true,
  "amounts": [1000, 1500, 2000, 2500, 3000, 3500, 5000, 10000],
  "currency": "BRL",
  "min_amount": 1000,
  "max_amount": 10000
}
```

A consulta de portabilidade é o que diz a operadora **atual** do número — não o
prefixo. `MockData.carrier(for:)` sorteia entre Vivo, Claro, TIM e Oi pelo hash
do número, o que erra sempre que houve portabilidade.

`amounts` é a tabela fechada da operadora: recarga de R$ 17,30 não existe. O app
hoje deixa digitar qualquer valor no teclado numérico.

Erros: `OPERADORA_NAO_IDENTIFICADA` (422), `NUMERO_INVALIDO` (422).

#### `POST /v1/payments/topup`

Requer `aal: 3` + `Idempotency-Key`. É o `RecargaFlow.commit()`.

```json
{ "phone": "+5511998733120", "carrier_id": "vivo", "amount": 3000, "currency": "BRL" }
```

`201`:
```json
{
  "transaction": {
    "id": "tx_9e0f1a2b-...",
    "title": "Recarga de celular",
    "counterparty": "Vivo · (11) 99873-3120",
    "amount": 3000,
    "currency": "BRL",
    "direction": "debit",
    "category": "outros",
    "method": "recarga",
    "state": "SETTLED",
    "auth_code": "E18236120202609261534C3D4E5F6A7B"
  },
  "topup": { "state": "CONFIRMED", "carrier_protocol": "VV-2026092600184412", "credited_at": "2026-09-26T15:34:22Z" },
  "balance_after": { "available": 173291, "currency": "BRL" }
}
```

`counterparty` no formato `"Vivo · (11) 99873-3120"` é exatamente o que o
`RecargaFlow` monta hoje (`"\(carrier) · \(phone)"`).

Erros: `VALOR_RECARGA_INVALIDO` (422, `details.allowed_amounts`),
`OPERADORA_INDISPONIVEL` (502), `SALDO_INSUFICIENTE`.

---

## 10. Cartões

### `GET /v1/cards`

```json
{
  "data": [
    {
      "id": "cd_7f3a2b1c",
      "kind": "fisico",
      "brand": "MASTERCARD",
      "masked_number": "•••• •••• •••• 4821",
      "last_four": "4821",
      "holder_name": "MARINA COSTA",
      "expiry": "09/31",
      "status": "ACTIVE",
      "is_blocked": false,
      "blocked_reason": null,
      "functions": ["credit", "debit"],
      "limit": 500000,
      "used_limit": 92570,
      "available_limit": 407430,
      "temporary_limit": null,
      "cashback": 3820,
      "contactless_enabled": true,
      "online_purchases_enabled": true,
      "international_enabled": false,
      "currency": "BRL",
      "current_invoice": {
        "id": "in_5f6a7b8c",
        "reference_month": "2026-09",
        "due_date": "2026-10-10",
        "state": "OPEN",
        "total_amount": 92570
      }
    },
    {
      "id": "cd_2b3c4d5e",
      "kind": "virtual",
      "brand": "MASTERCARD",
      "masked_number": "•••• •••• •••• 7712",
      "last_four": "7712",
      "holder_name": "MARINA COSTA",
      "expiry": "03/29",
      "status": "ACTIVE",
      "is_blocked": false,
      "parent_card_id": "cd_7f3a2b1c",
      "nickname": "Assinaturas",
      "functions": ["credit"],
      "limit": 500000,
      "currency": "BRL"
    }
  ]
}
```

**Nenhum endpoint devolve PAN ou CVV em campo comum.** `Card.number` e `Card.cvv`
precisam sair do modelo Swift.

### `POST /v1/cards/{id}/reveal`

Requer `aal: 3`. Exibição dos dados completos de cartão virtual.

`200`:
```json
{
  "session_token": "rvl_8f7e6d5c4b3a29180716",
  "expires_in": 60,
  "render_url": "https://secure.processor.com/pan-view?t=rvl_8f7e6d5c...",
  "mode": "IFRAME"
}
```

O PAN não passa pela nossa API nem pela nossa memória: o app abre um `WKWebView`
apontando para o `render_url` do processador, que renderiza os dados dentro de um
contexto isolado. É o que mantém o app fora do escopo PCI-DSS. `mode` pode ser
`IFRAME` ou `SDK_TOKEN` conforme o processador. Uso único, 60 s, auditado.

> **Hoje mockado:** `Card.displayNumber(revealed:)` devolve
> `"5412 7830 1195 2267"` — um PAN literal no binário. Além de não ser um cartão
> real, o padrão é insustentável: guardar PAN em struct do app coloca o app
> inteiro no escopo PCI-DSS.

### `POST /v1/cards/{id}/block` e `POST /v1/cards/{id}/unblock`

Requer `aal: 3` + `Idempotency-Key`.

```json
{ "reason": "USER", "note": "Perdi o cartão" }
```

`reason`: `USER` (temporário, reversível), `LOST`, `STOLEN`, `DAMAGED`
(definitivos, disparam segunda via).

`200`: `{ "id": "cd_7f3a2b1c", "is_blocked": true, "blocked_reason": "USER", "blocked_at": "2026-09-26T15:32:10Z", "can_unblock": true, "replacement_requested": false }`

Bloqueio é **imediato** no autorizador — não pode depender de batch.
`LOST`/`STOLEN` têm `can_unblock: false`.

Erros: `CARTAO_JA_BLOQUEADO` (409), `CARTAO_NAO_ENCONTRADO` (404),
`BLOQUEIO_NAO_REVERSIVEL` (409 no unblock).

### `POST /v1/cards/virtual`

Requer `aal: 3` + `Idempotency-Key`.

```json
{ "parent_card_id": "cd_7f3a2b1c", "nickname": "Assinaturas", "single_use": false, "spending_limit": 50000, "currency": "BRL" }
```

`201` devolve o cartão com `masked_number`; os dados completos só por `reveal`.
Máximo de 10 virtuais ativos (`LIMITE_CARTOES_VIRTUAIS` 422).

### `DELETE /v1/cards/virtual/{id}`

`204`. Cancelamento é definitivo.

### `PATCH /v1/cards/{id}/limit`

Requer `aal: 3`.

```json
{ "requested_limit": 800000, "currency": "BRL", "kind": "PERMANENT" }
```

`kind`: `PERMANENT` ou `TEMPORARY` (com `valid_until`).

Aprovado:
```json
{ "id": "cd_7f3a2b1c", "limit": 700000, "requested_limit": 800000, "approved_limit": 700000, "state": "APPROVED", "effective_at": "2026-09-26T15:32:10Z", "currency": "BRL" }
```

Redução vale na hora. Aumento passa por análise; pode aprovar parcialmente.

Erros: `LIMITE_SOLICITADO_NEGADO` (422, `details.max_approved`, `details.reason_code`),
`ANALISE_EM_ANDAMENTO` (409), `LIMITE_ABAIXO_DO_UTILIZADO` (422 — não dá para
reduzir abaixo da fatura em aberto).

### `GET /v1/cards/{id}/invoices`

```json
{
  "data": [
    {
      "id": "in_5f6a7b8c",
      "reference_month": "2026-09",
      "cycle_start": "2026-09-03",
      "cycle_end": "2026-10-02",
      "due_date": "2026-10-10",
      "state": "OPEN",
      "total_amount": 92570,
      "paid_amount": 0,
      "minimum_amount": 13886,
      "previous_balance": 0,
      "interest_amount": 0,
      "currency": "BRL"
    },
    {
      "id": "in_1a2b3c4d",
      "reference_month": "2026-08",
      "cycle_start": "2026-08-03",
      "cycle_end": "2026-09-02",
      "due_date": "2026-09-10",
      "state": "PAID",
      "total_amount": 118420,
      "paid_amount": 118420,
      "minimum_amount": 17763,
      "previous_balance": 0,
      "interest_amount": 0,
      "paid_at": "2026-09-08T11:22:04Z",
      "currency": "BRL"
    }
  ],
  "page": { "next_cursor": null, "has_more": false }
}
```

### `GET /v1/cards/{id}/invoices/{invoiceId}`

Mesmos campos, mais os itens:

```json
{
  "id": "in_5f6a7b8c",
  "reference_month": "2026-09",
  "due_date": "2026-10-10",
  "state": "OPEN",
  "total_amount": 92570,
  "minimum_amount": 13886,
  "currency": "BRL",
  "items": [
    { "transaction_id": "tx_1a2b3c4d-...", "occurred_at": "2026-09-26T15:05:12Z", "title": "Mercado Pão Fresco", "counterparty": "Compra no crédito", "amount": 8740,  "category": "mercado",      "installment": null },
    { "transaction_id": "tx_2b3c4d5e-...", "occurred_at": "2026-09-25T17:44:00Z", "title": "Assinatura de música", "counterparty": "Compra no crédito", "amount": 2190, "category": "assinaturas", "installment": null },
    { "transaction_id": "tx_3c4d5e6f-...", "occurred_at": "2026-09-21T11:30:21Z", "title": "Supermercado Vila", "counterparty": "Compra no crédito", "amount": 28460, "category": "mercado",      "installment": { "number": 1, "total": 3 } }
  ],
  "summary_by_category": [
    { "category": "mercado",      "total": 40020 },
    { "category": "restaurantes", "total": 26340 },
    { "category": "transporte",   "total": 21040 },
    { "category": "assinaturas",  "total": 2190 },
    { "category": "saude",        "total": 11900 }
  ],
  "payment_barcode": "34191790010104351004791020150008291070092570",
  "pdf_url": "https://api.aurora.com.br/v1/cards/cd_7f3a2b1c/invoices/in_5f6a7b8c/pdf?token=..."
}
```

`items` é o que substitui a varredura por string de `Ledger.creditInvoice`.

### `POST /v1/cards/{id}/invoices/{invoiceId}/payments`

Requer `aal: 3` + `Idempotency-Key`. É o `AppModel.payInvoice()`.

```json
{ "amount": 92570, "currency": "BRL", "source": "BALANCE" }
```

`source`: `BALANCE` (débito em conta) ou `BARCODE` (gera boleto para pagar em
outro banco).

`201`:
```json
{
  "transaction": {
    "id": "tx_4d5e6f7a-...",
    "title": "Pagamento de fatura",
    "counterparty": "Cartão Aurora",
    "amount": 92570,
    "currency": "BRL",
    "direction": "debit",
    "category": "credito",
    "method": "credito",
    "state": "SETTLED",
    "auth_code": "E18236120202609261540D4E5F6A7B8C"
  },
  "invoice": { "id": "in_5f6a7b8c", "state": "PAID", "paid_amount": 92570, "remaining": 0, "currency": "BRL" },
  "balance_after": { "available": 102461, "currency": "BRL" },
  "available_limit_after": 500000
}
```

`title: "Pagamento de fatura"` e `counterparty: "Cartão Aurora"` batem com
`Ledger.invoicePaymentTitle` e com o que `AppModel.payInvoice()` grava. Mas no
backend a baixa é por `invoice_id`, não pela string.

Pagamento parcial acima do mínimo → `state: "PARTIALLY_PAID"` e o restante entra
no rotativo do próximo ciclo com juros.

Erros: `SALDO_INSUFICIENTE`, `FATURA_JA_PAGA` (409), `FATURA_ABERTA_NAO_PAGAVEL`
(422 — só fatura fechada se paga), `VALOR_ABAIXO_DO_MINIMO` (422, `details.minimum`).

### `POST /v1/cards/{id}/invoices/{invoiceId}/installments`

Requer `aal: 3` + `Idempotency-Key`. É o `AppModel.installInvoice(months:)`.

Simulação primeiro, com `GET .../installments/simulation?terms=3,6,12`:

```json
{
  "invoice_amount": 92570,
  "currency": "BRL",
  "options": [
    { "months": 3,  "installment_amount": 32086, "total_amount": 96258,  "monthly_rate": 0.0199, "cet_annual": 0.2929, "iof_amount": 412 },
    { "months": 6,  "installment_amount": 16525, "total_amount": 99150,  "monthly_rate": 0.0199, "cet_annual": 0.2929, "iof_amount": 788 },
    { "months": 12, "installment_amount": 8790,  "total_amount": 105480, "monthly_rate": 0.0199, "cet_annual": 0.2929, "iof_amount": 1510 }
  ]
}
```

Contratação:
```json
{ "months": 6, "acknowledge_cet": true }
```

`201`:
```json
{
  "loan": {
    "id": "ln_8c9d0e1f",
    "origin": "INVOICE_INSTALLMENT",
    "origin_invoice_id": "in_5f6a7b8c",
    "principal": 92570,
    "monthly_rate": 0.0199,
    "installment_count": 6,
    "installment_amount": 16525,
    "iof_amount": 788,
    "cet_annual": 0.2929,
    "state": "ACTIVE",
    "first_due_date": "2026-11-10",
    "currency": "BRL"
  },
  "invoice": { "id": "in_5f6a7b8c", "state": "INSTALLED", "paid_amount": 92570 },
  "transactions": [
    { "id": "tx_5e6f7a8b-...", "title": "Pagamento de fatura",   "counterparty": "Parcelamento em 6x", "amount": 92570, "direction": "debit",  "method": "credito"   },
    { "id": "tx_6f7a8b9c-...", "title": "Crédito de parcelamento", "counterparty": "Fatura parcelada",  "amount": 92570, "direction": "credit", "method": "emprestimo" }
  ]
}
```

As duas transações espelham exatamente o que `AppModel.installInvoice` registra
hoje. A diferença: `acknowledge_cet` é obrigatório (exigência regulatória de
divulgação do CET), há IOF, e a `invoice` fica `INSTALLED` em vez de o app
simplesmente somar dois lançamentos e esquecer.

Erros: `FATURA_NAO_PARCELAVEL` (422), `PRAZO_INVALIDO` (422,
`details.allowed_terms`), `CET_NAO_ACEITO` (422), `CREDITO_NAO_APROVADO` (422).

---

## 11. Crédito

### `GET /v1/credit/score`

```json
{
  "score": 742,
  "range": { "min": 0, "max": 1000 },
  "band": "BOM",
  "updated_at": "2026-09-20T03:00:00Z",
  "next_update_at": "2026-10-20T03:00:00Z",
  "history": [
    { "month": "2026-09", "score": 742 },
    { "month": "2026-08", "score": 728 },
    { "month": "2026-07", "score": 731 },
    { "month": "2026-06", "score": 715 }
  ],
  "factors": [
    { "code": "PAYMENT_HISTORY",   "label": "Histórico de pagamentos", "impact": "POSITIVE", "weight": 0.35 },
    { "code": "CREDIT_UTILIZATION","label": "Uso do limite",           "impact": "NEUTRAL",  "weight": 0.30 },
    { "code": "ACCOUNT_AGE",       "label": "Tempo de relacionamento", "impact": "POSITIVE", "weight": 0.15 },
    { "code": "RECENT_INQUIRIES",  "label": "Consultas recentes",      "impact": "NEGATIVE", "weight": 0.10 }
  ],
  "preapproved": { "personal_loan_limit": 1500000, "card_limit_increase": 200000, "currency": "BRL" }
}
```

`742` é o valor do mock. `history` e `factors` não existem no app e são o que
torna a tela de score útil. Requer consentimento `CREDIT_BUREAU_QUERY` vigente;
sem ele, `403 CONSENTIMENTO_NECESSARIO`.

### `POST /v1/credit/loans/simulations`

```json
{ "principal": 500000, "currency": "BRL", "months": 12, "purpose": "PERSONAL" }
```

Ou por parcela desejada: `{ "installment_amount": 50000, "months": 12 }`.

`200`:
```json
{
  "simulation_id": "sim_7b8c9d0e",
  "principal": 500000,
  "currency": "BRL",
  "options": [
    { "months": 6,  "installment_amount": 90519,  "total_amount": 543114, "monthly_rate": 0.0249, "annual_rate": 0.3431, "cet_annual": 0.3812, "iof_amount": 1876, "first_due_date": "2026-10-26" },
    { "months": 12, "installment_amount": 48451,  "total_amount": 581412, "monthly_rate": 0.0249, "annual_rate": 0.3431, "cet_annual": 0.3798, "iof_amount": 3241, "first_due_date": "2026-10-26" },
    { "months": 24, "installment_amount": 27884,  "total_amount": 669216, "monthly_rate": 0.0249, "annual_rate": 0.3431, "cet_annual": 0.3776, "iof_amount": 5980, "first_due_date": "2026-10-26" }
  ],
  "approved_limit": 1500000,
  "expires_at": "2026-09-28T15:32:10Z"
}
```

`monthly_rate: 0.0249` é o `LoanFlow.monthlyRate` do app. As diferenças: a taxa
vem do servidor (personalizada pelo score, não fixa), `cet_annual` e `iof_amount`
existem, e `first_due_date` é `DATE` — o app calcula `firstDueDate()` como
`.now + 1 mês` no cliente, o que dá um instante, não um dia.

A simulação não é compromisso, mas é registrada: consulta a bureau é auditada.

Erros: `VALOR_ABAIXO_DO_MINIMO` (422), `CREDITO_NAO_APROVADO` (422,
`details.approved_limit`), `PRAZO_INVALIDO` (422).

### `POST /v1/credit/loans`

Requer `aal: 3` + `Idempotency-Key`. É o `LoanFlow.commit()`.

```json
{
  "simulation_id": "sim_7b8c9d0e",
  "months": 12,
  "acknowledge_cet": true,
  "signature": { "kind": "ELECTRONIC", "accepted_document_hash": "BASE64_SHA256_DA_CCB" }
}
```

`201`:
```json
{
  "loan": {
    "id": "ln_3e4f5a6b",
    "origin": "PERSONAL",
    "principal": 500000,
    "monthly_rate": 0.0249,
    "installment_count": 12,
    "installment_amount": 48451,
    "iof_amount": 3241,
    "cet_annual": 0.3798,
    "state": "DISBURSED",
    "contracted_at": "2026-09-26T15:32:10Z",
    "first_due_date": "2026-10-26",
    "outstanding": 581412,
    "currency": "BRL",
    "contract_document_url": "https://api.aurora.com.br/v1/credit/loans/ln_3e4f5a6b/contract.pdf?token=..."
  },
  "transaction": {
    "id": "tx_7a8b9c0d-...",
    "title": "Empréstimo pessoal",
    "counterparty": "12x de R$ 484,51",
    "amount": 500000,
    "currency": "BRL",
    "direction": "credit",
    "category": "credito",
    "method": "emprestimo",
    "state": "SETTLED",
    "auth_code": "E18236120202609261532E5F6A7B8C9D"
  },
  "balance_after": { "available": 695031, "currency": "BRL" },
  "installments": [
    { "id": "is_1a2b", "number": 1,  "total": 12, "amount": 48451, "principal_portion": 35995, "interest_portion": 12456, "due_date": "2026-10-26", "paid_at": null },
    { "id": "is_3c4d", "number": 2,  "total": 12, "amount": 48451, "principal_portion": 36891, "interest_portion": 11560, "due_date": "2026-11-26", "paid_at": null },
    { "id": "is_5e6f", "number": 12, "total": 12, "amount": 48453, "principal_portion": 47276, "interest_portion": 1177,  "due_date": "2027-09-26", "paid_at": null }
  ]
}
```

`counterparty: "12x de R$ 484,51"` reproduz o formato que `LoanFlow.commit` usa.
A última parcela é R$ 484,53, não R$ 484,51: a diferença de arredondamento vai
na última, de modo que a soma bata exatamente (invariante I-7). O app não faz isso.

Erros: `SIMULACAO_EXPIRADA` (409), `CREDITO_NAO_APROVADO` (422),
`CET_NAO_ACEITO` (422), `CONTRATO_NAO_ASSINADO` (422).

### `GET /v1/credit/loans`

```json
{
  "data": [
    {
      "id": "ln_3e4f5a6b",
      "origin": "PERSONAL",
      "principal": 500000,
      "installment_count": 12,
      "installment_amount": 48451,
      "paid_count": 2,
      "outstanding": 484510,
      "state": "ACTIVE",
      "contracted_at": "2026-09-26T15:32:10Z",
      "next_due": { "id": "is_5e6f", "number": 3, "total": 12, "amount": 48451, "due_date": "2026-12-26", "is_overdue": false },
      "currency": "BRL"
    }
  ],
  "summary": { "total_outstanding": 484510, "next_payment_date": "2026-12-26", "next_payment_amount": 48451, "currency": "BRL" }
}
```

`paid_count`, `outstanding` e `next_due` correspondem a `Loan.paidCount`,
`Loan.outstanding` e `Loan.nextDue`, mas calculados no servidor.

`GET /v1/credit/loans/{id}` traz o cronograma completo.

### `POST /v1/credit/loans/{id}/installments/{installmentId}/payments`

Requer `aal: 3` + `Idempotency-Key`. É o `AppModel.payNextInstallment()`.

```json
{ "amount": 48451, "currency": "BRL", "source": "BALANCE" }
```

`201`:
```json
{
  "transaction": {
    "id": "tx_8b9c0d1e-...",
    "title": "Parcela de empréstimo",
    "counterparty": "Parcela 3 de 12",
    "amount": 48451,
    "currency": "BRL",
    "direction": "debit",
    "category": "credito",
    "method": "emprestimo",
    "state": "SETTLED",
    "auth_code": "E18236120202609261545F6A7B8C9D0E"
  },
  "installment": { "id": "is_5e6f", "number": 3, "total": 12, "amount": 48451, "paid_amount": 48451, "paid_at": "2026-09-26T15:45:00Z", "late_fee": 0 },
  "loan": { "id": "ln_3e4f5a6b", "state": "ACTIVE", "paid_count": 3, "outstanding": 436059, "currency": "BRL" },
  "balance_after": { "available": 146580, "currency": "BRL" }
}
```

`counterparty: "Parcela 3 de 12"` é exatamente o `Installment.label` do Swift.

Parcela em atraso tem `late_fee` (multa de 2% + juros de mora de 1% a.m.) somada
ao `amount` devido — o app não tem noção de mora.

Erros: `PARCELA_JA_PAGA` (409 — invariante I-6), `SALDO_INSUFICIENTE`,
`PARCELA_NAO_ENCONTRADA` (404), `VALOR_DIVERGENTE` (422).

### `POST /v1/credit/loans/{id}/settlement/simulation`

Quitação antecipada com desconto proporcional dos juros futuros (direito do
consumidor, art. 52 §2º do CDC). Ausente no app.

```json
{ "loan_id": "ln_3e4f5a6b", "outstanding_nominal": 436059, "settlement_amount": 398720, "interest_discount": 37339, "valid_until": "2026-09-30", "currency": "BRL" }
```

---

## 12. Investimentos

### `GET /v1/investments/products`

Substitui o array estático `InvestmentProduct.all`.

```json
{
  "data": [
    {
      "id": "cdb",
      "name": "CDB Aurora",
      "rate": "110% do CDI",
      "liquidity": "diária",
      "liquidity_days": 0,
      "annual_yield": 0.1155,
      "accent": "accent",
      "asset_class": "RENDA_FIXA",
      "min_investment": 10000,
      "maturity_date": null,
      "is_tax_exempt": false,
      "risk_level": "BAIXO",
      "currency": "BRL"
    },
    {
      "id": "selic",
      "name": "Tesouro Selic 2029",
      "rate": "Selic + 0,05%",
      "liquidity": "D+1",
      "liquidity_days": 1,
      "annual_yield": 0.1055,
      "accent": "blue",
      "asset_class": "TESOURO",
      "min_investment": 10000,
      "maturity_date": "2029-03-01",
      "is_tax_exempt": false,
      "risk_level": "BAIXO",
      "currency": "BRL"
    },
    {
      "id": "lci",
      "name": "LCI Aurora 90 dias",
      "rate": "93% do CDI, isento de IR",
      "liquidity": "no vencimento",
      "liquidity_days": 90,
      "annual_yield": 0.0977,
      "accent": "purple",
      "asset_class": "RENDA_FIXA",
      "min_investment": 100000,
      "maturity_date": "2026-12-25",
      "is_tax_exempt": true,
      "risk_level": "BAIXO",
      "currency": "BRL"
    },
    {
      "id": "fii",
      "name": "Fundo Imobiliário AURA11",
      "rate": "Renda variável",
      "liquidity": "D+2",
      "liquidity_days": 2,
      "annual_yield": 0.0920,
      "accent": "amber",
      "asset_class": "FUNDO_IMOBILIARIO",
      "min_investment": 10000,
      "maturity_date": null,
      "is_tax_exempt": false,
      "risk_level": "ALTO",
      "currency": "BRL"
    }
  ]
}
```

Os slugs `cdb`, `selic`, `lci`, `fii` e os campos `rate`, `liquidity`,
`annual_yield` e `accent` são idênticos ao Swift, de propósito. `min_investment`,
`maturity_date`, `is_tax_exempt` e `risk_level` são novos e necessários.

`risk_level` exige perfil de investidor (suitability) compatível — um produto
`ALTO` não pode ser aplicado por quem tem perfil conservador sem termo de ciência
(CVM 30). O app não tem suitability nenhuma.

### `GET /v1/investments/holdings`

```json
{
  "data": [
    {
      "product_id": "cdb",
      "product_name": "CDB Aurora",
      "invested": 780000,
      "current": 820000,
      "earnings": 40000,
      "earnings_percent": 5.13,
      "gross_earnings": 40000,
      "income_tax_estimate": 6800,
      "iof_estimate": 0,
      "net_redemption_value": 813200,
      "applied_at": "2025-11-14T13:20:00Z",
      "available_at": "2026-09-27",
      "currency": "BRL"
    },
    {
      "product_id": "fii",
      "product_name": "Fundo Imobiliário AURA11",
      "invested": 150000,
      "current": 148000,
      "earnings": -2000,
      "earnings_percent": -1.33,
      "quantity": 14.82000000,
      "unit_price": 9987,
      "income_tax_estimate": 0,
      "iof_estimate": 0,
      "net_redemption_value": 148000,
      "applied_at": "2026-04-02T10:15:00Z",
      "available_at": "2026-09-30",
      "currency": "BRL"
    }
  ],
  "summary": { "total_invested": 1735000, "total_current": 1803000, "total_earnings": 68000, "earnings_percent": 3.92, "currency": "BRL" }
}
```

`earnings` e `earnings_percent` são derivados e o app já os calcula
(`Holding.earnings`, `Holding.earningsPercent`) — vêm na resposta para que os
dois lados concordem sobre o arredondamento.

`income_tax_estimate` (IR regressivo: 22,5% até 180 dias, 20% até 360, 17,5% até
720, 15% depois), `iof_estimate` (tabela regressiva nos primeiros 30 dias) e
`net_redemption_value` são o que o app precisa mostrar antes do resgate e hoje
não existem em lugar nenhum.

### `POST /v1/investments/applications`

Requer `aal: 3` + `Idempotency-Key`. É o `InvestFlow.commit()`.

```json
{ "product_id": "cdb", "amount": 100000, "currency": "BRL" }
```

`201`:
```json
{
  "transaction": {
    "id": "tx_9c0d1e2f-...",
    "title": "Aplicação",
    "counterparty": "CDB Aurora",
    "amount": 100000,
    "currency": "BRL",
    "direction": "debit",
    "category": "investimento",
    "method": "aplicacao",
    "state": "SETTLED",
    "auth_code": "E18236120202609261550A7B8C9D0E1F"
  },
  "holding": { "product_id": "cdb", "invested": 880000, "current": 920000, "currency": "BRL" },
  "balance_after": { "available": 95031, "currency": "BRL" },
  "settlement_date": "2026-09-26"
}
```

`title: "Aplicação"` e `counterparty` com o nome do produto reproduzem o
`InvestFlow.commit()`.

Erros: `SALDO_INSUFICIENTE`, `VALOR_ABAIXO_DO_MINIMO` (422, `details.minimum`),
`PRODUTO_INDISPONIVEL` (422 — fora do horário de negociação ou esgotado),
`PERFIL_INCOMPATIVEL` (422, `details.required_profile`).

### `POST /v1/investments/redemptions`

Requer `aal: 3` + `Idempotency-Key`. É o `RedeemFlow.commit()`.

```json
{ "product_id": "cdb", "amount": 50000, "currency": "BRL", "kind": "PARTIAL" }
```

`kind`: `PARTIAL` ou `TOTAL` (ignora `amount`).

`201`:
```json
{
  "transaction": {
    "id": "tx_0d1e2f3a-...",
    "title": "Resgate",
    "counterparty": "CDB Aurora",
    "amount": 49150,
    "currency": "BRL",
    "direction": "credit",
    "category": "investimento",
    "method": "aplicacao",
    "state": "AUTHORIZED",
    "auth_code": "E18236120202609261552B8C9D0E1F2A"
  },
  "redemption": {
    "gross_amount": 50000,
    "income_tax": 850,
    "iof": 0,
    "net_amount": 49150,
    "credit_date": "2026-09-27",
    "currency": "BRL"
  },
  "holding": { "product_id": "cdb", "invested": 830000, "current": 870000, "currency": "BRL" },
  "balance_after": { "available": 95031, "currency": "BRL" }
}
```

Note: `state: "AUTHORIZED"` e `balance_after` inalterado. A liquidez do CDB é
`diária` (D+0) mas do Tesouro é D+1 — `credit_date` diz quando o dinheiro chega.
O app hoje credita na hora, para qualquer produto, e o `RedeemFlow` nem mostra
IR. `holding.invested` diminui de forma proporcional ao custo médio, não pelo
truque de `min(invested, current)` que `AppModel.redeem` faz.

Erros: `POSICAO_INSUFICIENTE` (422), `PRODUTO_SEM_LIQUIDEZ` (422 — LCI no
carência, `details.available_at`), `VALOR_ABAIXO_DO_MINIMO`.

---

## 13. Cofrinhos

### `GET /v1/goals`

```json
{
  "data": [
    {
      "id": "go_1a2b3c4d",
      "name": "Viagem para o Chile",
      "saved": 320000,
      "target": 800000,
      "symbol": "airplane",
      "deadline": "2027-05-26",
      "progress": 0.40,
      "remaining": 480000,
      "is_complete": false,
      "yields_interest": false,
      "monthly_suggestion": 60000,
      "currency": "BRL",
      "created_at": "2026-02-14T09:00:00Z"
    },
    {
      "id": "go_5e6f7a8b",
      "name": "Reserva de emergência",
      "saved": 940000,
      "target": 1200000,
      "symbol": "shield.fill",
      "deadline": null,
      "progress": 0.7833,
      "remaining": 260000,
      "is_complete": false,
      "yields_interest": false,
      "monthly_suggestion": null,
      "currency": "BRL",
      "created_at": "2025-08-02T14:30:00Z"
    }
  ],
  "summary": { "total_saved": 1375000, "total_target": 2650000, "currency": "BRL" }
}
```

`progress`, `remaining` e `is_complete` são derivados que o app já calcula
(`Goal.progress`, `Goal.remaining`, `Goal.isComplete`) — vêm na resposta para
alinhar arredondamento. `monthly_suggestion` (`remaining / meses até o deadline`)
é novo e útil.

`saved` é o **saldo derivado da conta `GOAL`**, não um campo mutável
([01-dominio.md §3.2](01-dominio.md#32-como-registrar-um-débito-e-um-crédito)).

### `POST /v1/goals`

Requer `aal: 2` + `Idempotency-Key`. É o `AppModel.addGoal()`.

```json
{ "name": "Notebook novo", "target": 650000, "currency": "BRL", "symbol": "laptopcomputer", "deadline": "2027-02-26", "initial_deposit": 0 }
```

`201` devolve o cofrinho. `symbol` é validado contra uma lista de SF Symbols
permitidos — aceitar string livre deixaria o app renderizar um símbolo inexistente.

Erros: `DADOS_INVALIDOS`, `LIMITE_COFRINHOS_ATINGIDO` (422, máximo 20),
`SIMBOLO_INVALIDO` (422, `details.allowed_symbols`).

### `PATCH /v1/goals/{id}`

Requer `aal: 2`. Altera `name`, `target`, `symbol`, `deadline`.
Não altera `saved` — isso só por depósito/resgate.

### `DELETE /v1/goals/{id}`

Requer `aal: 3` (move dinheiro) + `Idempotency-Key`. É o `AppModel.deleteGoal()`.

`200`:
```json
{
  "goal_id": "go_9c0d1e2f",
  "archived": true,
  "refund": {
    "transaction": {
      "id": "tx_1e2f3a4b-...",
      "title": "Resgate do cofrinho",
      "counterparty": "Notebook novo",
      "amount": 115000,
      "currency": "BRL",
      "direction": "credit",
      "category": "investimento",
      "method": "cofrinho",
      "state": "SETTLED",
      "auth_code": "E18236120202609261555C9D0E1F2A3B"
    }
  },
  "balance_after": { "available": 210031, "currency": "BRL" }
}
```

`title: "Resgate do cofrinho"` reproduz o que `AppModel.deleteGoal()` registra
quando o cofrinho tem saldo. Exclusão é **arquivamento** — os lançamentos da
conta `GOAL` precisam sobreviver ao extrato histórico. `refund` é `null` se o
cofrinho estava zerado.

### `POST /v1/goals/{id}/deposits`

Requer `aal: 3` + `Idempotency-Key`. É o `GoalDepositFlow.commit()`.

```json
{ "amount": 20000, "currency": "BRL" }
```

`201`:
```json
{
  "transaction": {
    "id": "tx_2f3a4b5c-...",
    "title": "Guardado no cofrinho",
    "counterparty": "Viagem para o Chile",
    "amount": 20000,
    "currency": "BRL",
    "direction": "debit",
    "category": "investimento",
    "method": "cofrinho",
    "state": "SETTLED",
    "auth_code": "E18236120202609261557D0E1F2A3B4C"
  },
  "goal": { "id": "go_1a2b3c4d", "saved": 340000, "target": 800000, "progress": 0.425, "remaining": 460000, "is_complete": false, "currency": "BRL" },
  "balance_after": { "available": 175031, "currency": "BRL" }
}
```

Erros: `SALDO_INSUFICIENTE`, `VALOR_INVALIDO`, `COFRINHO_ARQUIVADO` (409).

### `POST /v1/goals/{id}/withdrawals`

Requer `aal: 3` + `Idempotency-Key`. É o `GoalWithdrawFlow.commit()`.

```json
{ "amount": 50000, "currency": "BRL" }
```

Resposta análoga, com `title: "Resgate do cofrinho"` e `direction: "credit"`.

Erros: `COFRINHO_SALDO_INSUFICIENTE` (422, `details.saved`). O app faz
`max(.zero, saved - amount)` em `AppModel.withdraw`, o que **silencia** o
estouro em vez de rejeitá-lo — no backend é erro (invariante I-3).

### `POST /v1/goals/{id}/automation`

Depósito automático recorrente. Ausente no app, mas é o que faz cofrinho funcionar.

```json
{ "kind": "FIXED_MONTHLY", "amount": 30000, "currency": "BRL", "day_of_month": 5, "enabled": true }
```

`kind`: `FIXED_MONTHLY`, `ROUND_UP` (arredonda cada compra e guarda o troco),
`PERCENT_OF_INCOME`.

---

## 14. Notificações

### `GET /v1/notifications`

Query: `?unread=true`, `?kind=transaction,security`, `limit`, `cursor`.

```json
{
  "data": [
    {
      "id": "nt_1a2b3c4d",
      "kind": "transaction",
      "title": "Pix recebido",
      "message": "R$ 150,00 de João Pedro Lima",
      "created_at": "2026-09-26T14:32:10Z",
      "read_at": null,
      "deep_link": "aurora://transaction/tx_0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0",
      "related": { "type": "transaction", "id": "tx_0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0" }
    },
    {
      "id": "nt_5e6f7a8b",
      "kind": "bill",
      "title": "Fatura fecha em 4 dias",
      "message": "Programe o pagamento para não pagar juros.",
      "created_at": "2026-09-26T07:45:00Z",
      "read_at": null,
      "deep_link": "aurora://card/cd_7f3a2b1c/invoice/in_5f6a7b8c",
      "related": { "type": "invoice", "id": "in_5f6a7b8c" }
    },
    {
      "id": "nt_9c0d1e2f",
      "kind": "security",
      "title": "Novo acesso reconhecido",
      "message": "iPhone 15 · São Paulo, SP",
      "created_at": "2026-09-25T14:22:00Z",
      "read_at": "2026-09-25T14:30:11Z",
      "deep_link": "aurora://settings/sessions",
      "related": { "type": "session", "id": "se_3f2a1b0c" }
    },
    {
      "id": "nt_3a4b5c6d",
      "kind": "offer",
      "title": "Seu limite pode aumentar",
      "message": "Score 742 libera análise de novo limite.",
      "created_at": "2026-09-24T13:00:00Z",
      "read_at": "2026-09-24T19:02:33Z",
      "deep_link": "aurora://card/cd_7f3a2b1c/limit",
      "related": null
    }
  ],
  "page": { "next_cursor": null, "has_more": false },
  "unread_count": 2
}
```

Os quatro itens correspondem exatamente aos de `AppModel.seedNotifications()`,
mas com `deep_link` e `related` — o que hoje falta para a notificação levar a
algum lugar. As notificações `offer` exigem consentimento `MARKETING` vigente.

### `POST /v1/notifications/{id}/read` e `POST /v1/notifications/read-all`

Requer `aal: 1` + `Idempotency-Key`.
`200`: `{ "id": "nt_1a2b3c4d", "read_at": "2026-09-26T15:32:10Z", "unread_count": 1 }`
O `read-all` (`AppModel.markAllNotificationsRead`) devolve `{ "marked": 2, "unread_count": 0 }`.

### `POST /v1/notifications/devices`

Registra o token APNs.

```json
{
  "install_id": "9f2b1c4e-...",
  "token": "a1b2c3d4e5f6...",
  "platform": "ios",
  "environment": "production",
  "bundle_id": "br.com.aurora.bank",
  "locale": "pt-BR",
  "timezone": "America/Sao_Paulo"
}
```

`201`: `{ "device_token_id": "dt_4d5e6f7a", "registered_at": "2026-09-26T15:32:10Z" }`

Reenviar a cada abertura do app — tokens APNs rotacionam. Token rejeitado pela
Apple é marcado `revoked_at` automaticamente.

### `DELETE /v1/notifications/devices/{id}`

`204`. Chamado no logout.

### `GET` / `PATCH /v1/notifications/preferences`

```json
{
  "channels": {
    "transaction": { "push": true,  "email": false, "sms": false },
    "security":    { "push": true,  "email": true,  "sms": true  },
    "bill":        { "push": true,  "email": true,  "sms": false },
    "offer":       { "push": false, "email": false, "sms": false }
  },
  "quiet_hours": { "enabled": true, "starts_at": "22:00", "ends_at": "07:00", "timezone": "America/Sao_Paulo" },
  "transaction_threshold": 5000,
  "currency": "BRL"
}
```

`security` não pode ser desligado — alerta de fraude é obrigatório. Tentar
desligar devolve `422 CANAL_OBRIGATORIO`. `transaction_threshold` corresponde ao
toggle `Settings.transactionAlerts`, mas com valor mínimo em vez de liga/desliga.

---

## 15. Suporte

### `POST /v1/support/tickets`

Requer `aal: 1` + `Idempotency-Key`.

```json
{
  "subject": "Não reconheço uma compra",
  "category": "TRANSACTION_DISPUTE",
  "description": "Não reconheço a compra de R$ 312,80 no Supermercado Vila do dia 21.",
  "related": { "type": "transaction", "id": "tx_3c4d5e6f-..." },
  "attachments": ["up_1a2b3c4d"]
}
```

`category`: `TRANSACTION_DISPUTE`, `CARD_ISSUE`, `PIX_ISSUE`, `LOAN_ISSUE`,
`ACCOUNT_ACCESS`, `COMPLAINT`, `OMBUDSMAN`, `OTHER`.

`201`:
```json
{
  "id": "tk_5e6f7a8b",
  "protocol": "2026092600184412",
  "subject": "Não reconheço uma compra",
  "category": "TRANSACTION_DISPUTE",
  "state": "OPEN",
  "priority": "HIGH",
  "sla_deadline": "2026-09-31T15:32:10Z",
  "created_at": "2026-09-26T15:32:10Z",
  "assigned_channel": "HUMAN"
}
```

`protocol` é o número que o cliente cita, obrigatório pelo Decreto 11.034.
`sla_deadline` para chamado de PF é 5 dias úteis; ouvidoria, 10.
`assigned_channel`: `BOT` (FAQ resolve) ou `HUMAN`.

### `GET /v1/support/tickets`

Query: `?state=OPEN,IN_PROGRESS`, `limit`, `cursor`.

```json
{
  "data": [
    {
      "id": "tk_5e6f7a8b",
      "protocol": "2026092600184412",
      "subject": "Não reconheço uma compra",
      "category": "TRANSACTION_DISPUTE",
      "state": "IN_PROGRESS",
      "priority": "HIGH",
      "unread_messages": 1,
      "last_message_at": "2026-09-26T16:10:22Z",
      "sla_deadline": "2026-09-31T15:32:10Z",
      "created_at": "2026-09-26T15:32:10Z"
    }
  ],
  "page": { "next_cursor": null, "has_more": false }
}
```

Estados: `OPEN` → `IN_PROGRESS` → `WAITING_CUSTOMER` → `RESOLVED` → `CLOSED`.
`REOPENED` é possível em até 30 dias do `RESOLVED`.

### `GET /v1/support/tickets/{id}/messages`

```json
{
  "data": [
    {
      "id": "ms_1a2b3c4d",
      "author": { "kind": "CUSTOMER", "name": "Marina Costa" },
      "body": "Não reconheço a compra de R$ 312,80 no Supermercado Vila do dia 21.",
      "attachments": [],
      "created_at": "2026-09-26T15:32:10Z",
      "read_at": "2026-09-26T15:40:00Z"
    },
    {
      "id": "ms_5e6f7a8b",
      "author": { "kind": "AGENT", "name": "Carla", "agent_id": "ag_0099" },
      "body": "Oi, Marina. Abri a contestação dessa compra. O valor foi bloqueado no cartão e você recebe o retorno em até 7 dias úteis. Protocolo 2026092600184412.",
      "attachments": [],
      "created_at": "2026-09-26T16:10:22Z",
      "read_at": null
    }
  ],
  "page": { "next_cursor": null, "has_more": false }
}
```

`author.kind`: `CUSTOMER`, `AGENT`, `BOT`, `SYSTEM`.

### `POST /v1/support/tickets/{id}/messages`

Requer `Idempotency-Key`.

```json
{ "body": "Obrigada! Vou aguardar.", "attachments": [] }
```

`201` devolve a mensagem. Erro: `CHAMADO_ENCERRADO` (409).

### `POST /v1/support/uploads`

`multipart/form-data`, ≤ 10 MB, JPEG/PNG/PDF.
`201`: `{ "id": "up_1a2b3c4d", "filename": "comprovante.pdf", "size_bytes": 184203, "expires_at": "2026-09-27T15:32:10Z" }`
Anexo não referenciado em 24h é apagado.

### `POST /v1/support/tickets/{id}/rating`

```json
{ "csat": 5, "nps": 9, "comment": "Resolveram rápido." }
```

`204`. Só em ticket `RESOLVED` ou `CLOSED`.

---

## 16. Webhooks

### 16.1 Recebidos pelo backend

Todos em `POST /webhooks/{provider}/{event}`, expostos em endpoint separado do
tráfego de app, com IP allowlist, mTLS e assinatura.

| Provedor | Evento | Efeito |
|---|---|---|
| SPI/Pix | `pix.payment.settled` | `AUTHORIZED` → `SETTLED`; push ao cliente |
| SPI/Pix | `pix.payment.rejected` | `AUTHORIZED` → `FAILED`; lançamentos de reversão |
| SPI/Pix | `pix.payment.received` | Cria transação de crédito; push |
| SPI/Pix | `pix.refund.settled` | Marca devolução liquidada |
| SPI/Pix | `pix.med.opened` | Bloqueia valor; notificação `security` |
| DICT | `dict.key.registered` / `dict.key.claim` | Atualiza `pix_keys.state` |
| CIP | `boleto.payment.confirmed` | `AUTHORIZED` → `SETTLED` |
| CIP | `boleto.payment.rejected` | `AUTHORIZED` → `FAILED`; devolve o valor |
| Processador | `card.authorization.requested` | **Síncrona**: decide aprovar/negar em < 2 s |
| Processador | `card.authorization.captured` | `AUTHORIZED` → `SETTLED`; entra na fatura |
| Processador | `card.authorization.reversed` | `AUTHORIZED` → `REVERSED` |
| Processador | `card.chargeback.opened` | Abre disputa; notificação |
| KYC | `kyc.analysis.completed` | Avança a proposta |
| Bureau | `credit.score.updated` | Atualiza `users.credit_score` |
| Custodiante | `investment.settlement.completed` | Credita o resgate |

**Autorização de cartão é síncrona**, não fire-and-forget. O processador espera
uma resposta em menos de 2 segundos:

```json
{
  "event": "card.authorization.requested",
  "event_id": "ev_0f1e2d3c",
  "occurred_at": "2026-09-26T15:32:10Z",
  "data": {
    "card_token": "tok_9f8e7d6c",
    "amount": 8740,
    "currency": "BRL",
    "merchant": { "name": "MERCADO PAO FRESCO", "mcc": "5411", "city": "SAO PAULO", "country": "BRA" },
    "authorization_id": "auth_5a4b3c2d",
    "function": "credit",
    "installments": 1,
    "is_contactless": true,
    "is_online": false
  }
}
```

Resposta esperada:
```json
{ "decision": "APPROVE", "approved_amount": 8740, "authorization_code": "A1B2C3", "reason_code": null }
```

Ou `{ "decision": "DECLINE", "reason_code": "INSUFFICIENT_FUNDS" }`.
Timeout do nosso lado = `stand-in` do processador segundo regras pré-acordadas.

**Contrato dos webhooks recebidos:**

- Assinatura `X-Signature: t=1758901930,v1=<hmac_sha256>` verificada em tempo
  constante, com tolerância de 5 minutos no timestamp.
- `event_id` é a chave de idempotência: evento repetido devolve `200` sem
  reprocessar. Provedores **reenviam** — assumir entrega exatamente-uma-vez é
  o erro clássico.
- Resposta `2xx` em menos de 5 s (2 s para autorização de cartão). O trabalho
  pesado vai para fila; o webhook só persiste o evento e enfileira.
- Ordem não é garantida. Um `settled` pode chegar antes do `authorized` — a
  máquina de estados precisa tolerar, guardando o evento fora de ordem para
  reprocessar.

### 16.2 Publicados pelo backend

Barramento interno (Kafka/SNS) que alimenta push, e-mail, antifraude, analytics
e o data lake. Publicados via **outbox transacional**: o evento é gravado na
mesma transação SQL da mudança de estado e despachado depois por um relay. Sem
isso, existe a janela clássica em que o banco commitou e o evento se perdeu.

| Evento | Payload principal | Consome |
|---|---|---|
| `transaction.created` | transação completa | Push, antifraude, analytics |
| `transaction.settled` | id, estado, saldo novo | Push, extrato em tempo real |
| `transaction.failed` | id, `failure_code` | Push, suporte |
| `transaction.reversed` | id, transação de estorno | Push, contabilidade |
| `balance.changed` | conta, saldo novo, delta | Cache, widget iOS |
| `pix.key.registered` / `pix.key.deleted` | chave mascarada | Push |
| `card.blocked` / `card.unblocked` | cartão, motivo | Push, antifraude |
| `invoice.closed` | fatura, total, vencimento | Push "Fatura fechou" |
| `invoice.due_soon` | fatura, dias restantes | Push "Fatura fecha em 4 dias" |
| `invoice.overdue` | fatura, encargos | Push, cobrança |
| `loan.contracted` | contrato completo | Push, contabilidade, bureau |
| `loan.installment.due_soon` | parcela, dias | Push |
| `loan.installment.paid` | parcela, contrato | Push |
| `loan.delinquent` | contrato, dias em atraso | Cobrança, bureau |
| `goal.completed` | cofrinho, valor | Push "Você bateu a meta!" |
| `investment.yield.credited` | posição, rendimento | Extrato |
| `security.new_device` | device, IP, cidade | Push, e-mail, SMS |
| `security.pin_changed` | device | Push, e-mail |
| `security.suspicious_activity` | operação, score de risco | Antifraude, bloqueio |
| `kyc.approved` / `kyc.rejected` | proposta | Onboarding |
| `credit.score.updated` | score novo e anterior | Push se subiu de faixa |

O evento `invoice.due_soon` é o que gera a notificação "Fatura fecha em 4 dias"
que hoje está literal em `AppModel.seedNotifications()`.

**Contrato dos eventos publicados:**

- Envelope: `{ "event_id", "event_type", "version", "occurred_at", "user_id", "trace_id", "data" }`.
- `version` no envelope; campo novo é compatível, remoção exige versão nova.
- Consumidores precisam ser idempotentes por `event_id` — a entrega é
  ao-menos-uma-vez.
- Nenhum evento carrega PAN, CPF completo, PIN ou token. Ids e valores mascarados.

---

## 17. Resumo do que o app precisa mudar

| Área | Mudança no app |
|---|---|
| `Money` | `Codable` para centavos inteiros, não `Decimal` cru |
| `Transaction` | Ganhar `state`, `direction`; `amount` vira positivo + direção |
| `Transaction.newAuthCode()` | Remover — o `auth_code` vem do servidor |
| `Card` | Remover `number`, `cvv`, `expiry`; usar `reveal` via webview |
| `Ledger` | Inicializar com saldo pronto; extrato paginado, não array completo |
| `Ledger.creditInvoice` | Remover — vem em `card.invoice_amount` |
| `Installment.dueDate`, `Goal.deadline` | Virar data de calendário, não `Date` |
| `InvestmentProduct.all` | Remover — vem de `GET /v1/investments/products` |
| `SecurityService.verifyPIN` | Deixar de decidir; passar a derivar prova para o servidor |
| `KeychainSecurityService.hashed` | Trocar FNV-1a por Argon2id |
| Biometria | Registrar chave da Secure Enclave e assinar challenges |
| `FlowSession` | Gerar `Idempotency-Key` no passo `.pin` |
| `FlowContext.isNight()` | Usar `server_time` e `America/Sao_Paulo` |
| `AppModel.*` (mutações) | Deixar de mutar localmente; aplicar a resposta do servidor |
| Enums | Tolerar valores desconhecidos sem quebrar o parse |

---

Modelo de dados por trás desta API: [01-dominio.md](01-dominio.md).

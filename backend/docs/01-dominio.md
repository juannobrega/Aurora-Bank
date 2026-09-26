# 01 — Modelo de domínio e dados

> **Status: especificação.** Nada descrito aqui existe ainda. O app iOS roda
> hoje inteiramente sobre `MockAccountService` e `AppModel`, que mantêm o
> estado em memória. Este documento descreve o que o backend precisa construir
> para substituir esse mock sem que nenhuma view do app mude.

O vocabulário aqui é o mesmo do código Swift em `IOS APP/Aurora/Aurora/Models`.
Quando o Swift chama um campo de `counterparty`, `authCode` ou `method`, o banco
e a API chamam igual. Divergência de nome entre cliente e servidor é dívida que
se paga com bug de serialização.

---

## 1. Visão geral das entidades

| Entidade | Origem no app | Papel | Mutável? |
|---|---|---|---|
| `User` | `Account.swift` | Titular pessoa física, CPF, agência/conta | Sim (dados cadastrais) |
| `Account` | implícita (`agency`/`account` em `User`) | Conta corrente; raiz de todo saldo | Sim (status) |
| `LedgerEntry` | **não existe no app** | Lançamento contábil atômico (débito ou crédito) | **Não — append-only** |
| `Transaction` | `Transaction.swift` | Fato de negócio visível no extrato; agrupa 2+ `LedgerEntry` | Estado sim, valor não |
| `Card` | `Account.swift` | Cartão físico ou virtual | Sim |
| `Invoice` | derivada em `Ledger.creditInvoice` | Fatura de cartão de crédito por ciclo | Sim até fechar |
| `Holding` | `Account.swift` | Posição do cliente num produto de investimento | Sim |
| `InvestmentProduct` | `Account.swift` (`InvestmentProduct.all` hardcoded) | Catálogo de produtos | Sim (admin) |
| `Goal` | `Account.swift` | Cofrinho / reserva com objetivo | Sim |
| `Loan` | `Account.swift` | Contrato de empréstimo pessoal | Estado sim, termos não |
| `Installment` | `Account.swift` | Parcela de um `Loan` | Sim até ser paga; depois imutável |
| `PixKey` | `Account.swift` | Chave Pix do titular no DICT | Não (cria/exclui) |
| `Contact` | `Account.swift` | Favorecido salvo para reuso | Sim |
| `Notification` | `AppModel.swift` (`AppNotification`) | Item da central de mensagens | Só `read_at` |
| `Consent` | **não existe no app** | Aceite de termo/política/LGPD, versionado | **Não — append-only** |
| `Device` | parcialmente em `SecurityService` | Aparelho confiável vinculado ao usuário | Sim (status) |
| `AuditLog` | **não existe no app** | Trilha de tudo que tocou dinheiro ou dado sensível | **Não — append-only** |

Entidades de apoio que o app não conhece mas o backend precisa:
`IdempotencyKey`, `BalanceSnapshot`, `Session`, `RefreshToken`, `AuthChallenge`,
`OnboardingProposal`, `KycDocument`, `WebhookEvent`, `OutboxEvent`, `SupportTicket`,
`SupportMessage`, `PixLimit`, `ScheduledPayment`, `DeviceToken`.

### Relacionamentos

```
User 1──N Account 1──N LedgerEntry N──1 Transaction
 │          │
 │          ├──N Card 1──N Invoice
 │          ├──N Holding N──1 InvestmentProduct
 │          ├──N Goal
 │          └──N Loan 1──N Installment
 ├──N PixKey
 ├──N Contact
 ├──N Device 1──N Session
 ├──N Consent
 ├──N Notification
 └──N SupportTicket 1──N SupportMessage
```

Toda `Transaction` tem N `LedgerEntry` (N ≥ 2) cuja soma é zero.
Todo `Goal` e todo `Holding` são, no ledger, **contas internas do usuário** — não
campos soltos. Isso é a correção principal em relação ao app, explicada na seção 3.

---

## 2. Dicionário de dados

Convenções para todas as tabelas:

- PK é `UUID` (`uuid` no PostgreSQL), gerado pelo servidor, exceto onde dito.
- Toda tabela tem `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`.
- Tabelas mutáveis têm `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`.
- Tabelas append-only **não têm** `updated_at` — a ausência é intencional e
  reforçada por trigger que rejeita `UPDATE` e `DELETE`.
- Dinheiro é `NUMERIC(18,2)` sempre (ver seção 8).
- Datas com hora são `TIMESTAMPTZ` em UTC; datas de calendário são `DATE` (ver seção 9).

### 2.1 `users`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `name` | `text` | sim | `User.name`. `firstName` e `initials` são derivados no cliente — não persistir. |
| `cpf` | `char(11)` | sim | **Só dígitos no banco.** O app exibe `482.917.330-12`; a máscara é de apresentação. `UNIQUE`. |
| `cpf_hash` | `bytea` | sim | HMAC-SHA256 do CPF com chave em KMS, para busca sem expor o índice. |
| `email` | `citext` | sim | `UNIQUE`. |
| `email_verified_at` | `timestamptz` | não | |
| `phone` | `varchar(16)` | sim | E.164 (`+5511998733120`). O app mostra `(11) 99873-3120`. |
| `phone_verified_at` | `timestamptz` | não | |
| `birth_date` | `date` | sim | Exigido no KYC; hoje ausente no app. |
| `mother_name` | `text` | não | Exigido por alguns parceiros de KYC. |
| `status` | `user_status` | sim | `PENDING_KYC`, `ACTIVE`, `BLOCKED`, `CLOSED`. |
| `monthly_budget` | `numeric(18,2)` | sim | `AppModel.monthlyBudget`, default `4000.00`. Preferência, não dinheiro real. |
| `credit_score` | `smallint` | não | `AppModel.creditScore` (742 no mock). Calculado pelo backend, nunca escrito pelo app. |
| `credit_score_updated_at` | `timestamptz` | não | |
| `settings` | `jsonb` | sim | Espelha `Settings` do Swift: `biometricsEnabled`, `hideBalanceOnOpen`, `transactionAlerts`, `nightLimitEnabled`, `nightLimit` (em centavos). Default `'{}'`. |
| `created_at` / `updated_at` | `timestamptz` | sim | |

> **Hoje mockado:** `credit_score` é a constante `742` em `AppModel`. O backend
> precisa de um serviço real de score (bureau + comportamento interno) com
> histórico — o app já tem tela para exibir a evolução.

### 2.2 `accounts`

O app trata conta como dois campos em `User` (`agency = "0001"`, `account = "482917-3"`).
O backend precisa de uma entidade, porque existem contas internas que não são a
conta corrente.

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `user_id` | `uuid` FK → `users` | sim | |
| `kind` | `account_kind` | sim | `CHECKING`, `GOAL`, `INVESTMENT`, `CARD_LIABILITY`, `LOAN_LIABILITY`. Ver seção 3. |
| `agency` | `char(4)` | sim | `0001`. |
| `number` | `varchar(12)` | sim | Sem dígito verificador. |
| `check_digit` | `char(1)` | sim | O app exibe junto: `482917-3`. |
| `ispb` | `char(8)` | sim | ISPB da instituição, para Pix/TED. |
| `currency` | `char(3)` | sim | `BRL`. Reservado para multimoeda futura. |
| `status` | `account_status` | sim | `ACTIVE`, `FROZEN`, `CLOSED`. |
| `opening_balance` | `numeric(18,2)` | sim | `Ledger.openingBalance` (`1950.31` no mock). Migração inicial, imutável depois. |
| `owner_ref_type` | `text` | não | Para contas internas: `GOAL`, `HOLDING`, `LOAN`, `CARD`. |
| `owner_ref_id` | `uuid` | não | Id da `Goal`/`Holding`/`Loan`/`Card` correspondente. |

`UNIQUE (agency, number, check_digit)`. Índice em `(user_id, kind)`.

### 2.3 `ledger_entries` — append-only

O coração do sistema. **Não existe equivalente no app**, que usa apenas
`Transaction` com `amount` assinado.

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `transaction_id` | `uuid` FK → `transactions` | sim | Todo lançamento pertence a uma transação. |
| `account_id` | `uuid` FK → `accounts` | sim | Conta afetada. |
| `direction` | `entry_direction` | sim | `DEBIT` ou `CREDIT`. |
| `amount` | `numeric(18,2)` | sim | **Sempre positivo.** O sinal vive em `direction`. |
| `currency` | `char(3)` | sim | `BRL`. |
| `sequence` | `bigint` | sim | Sequência global monotônica (`BIGSERIAL`), define ordem canônica. |
| `posted_at` | `timestamptz` | sim | Quando o lançamento passou a valer. |
| `effective_date` | `date` | sim | Data contábil em `America/Sao_Paulo`. Usada no extrato. |
| `created_at` | `timestamptz` | sim | |

Índices: `(account_id, posted_at DESC, sequence DESC)` para extrato e saldo;
`(transaction_id)` para montar a transação; `(account_id, effective_date)` para
fechamento diário.

Trigger `BEFORE UPDATE OR DELETE` levanta exceção. Correção contábil se faz com
lançamento de estorno, nunca com `UPDATE`.

### 2.4 `transactions`

Espelha `Transaction.swift`, mas com estado e valor derivado dos lançamentos.

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | Corresponde a `Transaction.id` (UUID no Swift). |
| `user_id` | `uuid` FK → `users` | sim | |
| `primary_account_id` | `uuid` FK → `accounts` | sim | Conta do ponto de vista de quem vê o extrato. |
| `title` | `text` | sim | `Transaction.title`. Ex.: `"Pix enviado"`, `"Pagamento de fatura"`. |
| `counterparty` | `text` | sim | `Transaction.counterparty`. Ex.: `"Ana Luiza Prado"`, `"Compra no crédito"`. |
| `counterparty_document` | `varchar(14)` | não | CPF/CNPJ do outro lado quando conhecido (Pix, TED, boleto). |
| `counterparty_bank` | `text` | não | `Contact.bank`. |
| `category` | `category` | sim | Enum abaixo. Corresponde a `Category`. |
| `method` | `payment_method` | sim | Enum abaixo. Corresponde a `PaymentMethod`. |
| `state` | `transaction_state` | sim | Máquina de estados da seção 5. |
| `direction_hint` | `entry_direction` | sim | Sinal do ponto de vista de `primary_account_id`. Denormalização para filtrar "só entradas" sem join. |
| `amount` | `numeric(18,2)` | sim | Valor absoluto. Denormalizado da perna principal; **fonte de verdade continua sendo o ledger**, reconciliado por job. |
| `auth_code` | `varchar(35)` | sim | `Transaction.authCode`. Formato E2E do Pix: `E` + 31 hex maiúsculos. Para não-Pix, código interno no mesmo formato. `UNIQUE`. |
| `external_id` | `text` | não | `endToEndId` do SPI, `nosso número` do boleto, `authorizationId` do adquirente. |
| `scheduled_for` | `timestamptz` | não | `PixFlow.scheduledFor`. Nulo = imediata. |
| `occurred_at` | `timestamptz` | sim | `Transaction.date`. |
| `settled_at` | `timestamptz` | não | Preenchido ao entrar em `SETTLED`. |
| `reversed_by_transaction_id` | `uuid` FK → `transactions` | não | Preenchido no estorno/MED. |
| `failure_code` | `text` | não | Código de erro do domínio quando `FAILED`. |
| `note` | `text` | não | Descrição digitada pelo usuário no Pix. |
| `device_id` | `uuid` FK → `devices` | não | De qual aparelho partiu. Antifraude e auditoria. |
| `idempotency_key_id` | `uuid` FK → `idempotency_keys` | não | Qual chave criou esta transação. |
| `metadata` | `jsonb` | sim | Payload específico do método (linha digitável, QR, id do produto). Default `'{}'`. |
| `created_at` / `updated_at` | `timestamptz` | sim | |

Índices: `(user_id, occurred_at DESC)`, `(auth_code)`, `(external_id)`,
`(user_id, category, occurred_at)` para o gráfico de gastos,
GIN em `to_tsvector('portuguese', title || ' ' || counterparty)` para a busca do extrato.

**Enum `category`** — exatamente o `Category` do Swift:
`moradia`, `mercado`, `restaurantes`, `transporte`, `assinaturas`, `saude`,
`educacao`, `lazer`, `transferencia`, `investimento`, `salario`, `rendimento`,
`credito`, `outros`.

A propriedade `isSpending` do Swift (falsa para `salario`, `rendimento`, `credito`,
`investimento`) é regra de negócio: precisa existir igual no backend, porque o
orçamento mensal e o gráfico de gastos dependem dela. Materializar como coluna
de uma tabela `categories` para não duplicar o `switch` em dois lugares.

**Enum `payment_method`** — exatamente o `PaymentMethod` do Swift:
`pix`, `debito`, `credito`, `boleto`, `ted`, `cofrinho`, `aplicacao`, `emprestimo`, `recarga`.

> **Hoje mockado:** `Transaction.newAuthCode()` gera 31 hex aleatórios no
> dispositivo. No backend, o `auth_code` de um Pix é o `endToEndId` devolvido
> pelo SPI, não um número inventado pelo cliente. O app precisa parar de gerar
> e passar a ler o que o servidor devolve.

### 2.5 `balance_snapshots`

Otimização de leitura. Ver seção 3.4 — não é fonte de verdade.

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `account_id` | `uuid` FK → `accounts` | sim | |
| `balance` | `numeric(18,2)` | sim | Saldo acumulado **até e incluindo** `last_sequence`. |
| `last_sequence` | `bigint` | sim | Maior `ledger_entries.sequence` incluído. |
| `entry_count` | `bigint` | sim | Quantos lançamentos entraram. Verificação cruzada. |
| `snapshot_at` | `timestamptz` | sim | |
| `kind` | `snapshot_kind` | sim | `ROLLING` (mais recente, sobrescrito) ou `DAILY_CLOSE` (histórico, imutável). |

`UNIQUE (account_id, kind) WHERE kind = 'ROLLING'`.
`UNIQUE (account_id, snapshot_at::date) WHERE kind = 'DAILY_CLOSE'`.

### 2.6 `cards`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `user_id` | `uuid` FK → `users` | sim | |
| `liability_account_id` | `uuid` FK → `accounts` | sim | Conta `CARD_LIABILITY` deste cartão. |
| `kind` | `card_kind` | sim | `fisico` \| `virtual` — igual a `Card.Kind`. |
| `brand` | `text` | sim | `MASTERCARD`, `VISA`, `ELO`. |
| `last_four` | `char(4)` | sim | `4821` no mock. Único pedaço do PAN que o backend guarda. |
| `pan_token` | `text` | sim | Token do processador. **Nunca o PAN.** Ver abaixo. |
| `expiry_month` | `smallint` | sim | `09` no mock. |
| `expiry_year` | `smallint` | sim | `2031`. |
| `is_blocked` | `boolean` | sim | `Card.isBlocked`. Default `false`. |
| `blocked_reason` | `text` | não | `USER`, `FRAUD`, `LOST`, `STOLEN`. |
| `credit_limit` | `numeric(18,2)` | sim | `Card.limit` (`5000.00`). Autoridade do backend. |
| `temporary_limit` | `numeric(18,2)` | não | Ajuste temporário. |
| `temporary_limit_until` | `date` | não | |
| `invoice_closing_day` | `smallint` | sim | Dia do fechamento. |
| `invoice_due_day` | `smallint` | sim | Dia do vencimento — `10` no mock (`MockData.nextTenth()`). |
| `cashback_balance` | `numeric(18,2)` | sim | `Card.cashback` (`38.20`). Default `0`. |
| `parent_card_id` | `uuid` FK → `cards` | não | Cartão adicional / virtual derivado do físico. |
| `status` | `card_status` | sim | `REQUESTED`, `SHIPPED`, `ACTIVE`, `BLOCKED`, `CANCELLED`. |

> **Hoje mockado, e é o ponto mais grave da migração:** `Card` no Swift carrega
> `number = "5412 7830 1195 2267"`, `cvv = "318"` e `expiry = "09/31"` como
> literais, e `displayNumber(revealed:)` mostra o PAN em claro para cartão
> virtual. O backend **não pode** armazenar PAN nem CVV — exigência de PCI-DSS.
> O padrão correto: o processador emite os dados; o app os obtém por um endpoint
> de curta duração que devolve um token de exibição consumível uma única vez, ou
> renderiza via SDK do processador. `Card.number` e `Card.cvv` devem sair do
> modelo do app.

### 2.7 `invoices`

`Card.invoiceDue` no app é só uma data, e o valor da fatura é calculado por
`Ledger.creditInvoice` varrendo transações para trás até achar um título igual a
`"Pagamento de fatura"`. Isso é frágil (depende de string) e não tem ciclo.

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `card_id` | `uuid` FK → `cards` | sim | |
| `reference_month` | `date` | sim | Primeiro dia do mês de competência. |
| `cycle_start` | `date` | sim | |
| `cycle_end` | `date` | sim | Data de fechamento. |
| `due_date` | `date` | sim | **`DATE`, não timestamp.** Ver seção 9. |
| `state` | `invoice_state` | sim | `OPEN`, `CLOSED`, `PAID`, `PARTIALLY_PAID`, `OVERDUE`, `INSTALLED`. |
| `total_amount` | `numeric(18,2)` | sim | Soma das compras do ciclo. Derivada. |
| `paid_amount` | `numeric(18,2)` | sim | Default `0`. |
| `minimum_amount` | `numeric(18,2)` | sim | Regulatório: mínimo de 15%. |
| `previous_balance` | `numeric(18,2)` | sim | Rotativo vindo do ciclo anterior. |
| `interest_amount` | `numeric(18,2)` | sim | Juros do rotativo. Default `0`. |
| `closed_at` | `timestamptz` | não | |
| `paid_at` | `timestamptz` | não | |
| `installment_loan_id` | `uuid` FK → `loans` | não | Preenchido quando a fatura é parcelada. |

`UNIQUE (card_id, reference_month)`.

Ligação fatura ↔ compras: `invoice_items (invoice_id, transaction_id)`, PK composta.
Cada compra no crédito entra em exatamente uma fatura. Isso substitui a varredura
por string que o app faz hoje.

### 2.8 `investment_products`

Hoje é `InvestmentProduct.all`, um array estático no Swift com quatro produtos.

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `varchar(32)` PK | sim | Slug: `cdb`, `selic`, `lci`, `fii`. **O app referencia `Holding.id == InvestmentProduct.id`** — manter os mesmos slugs na migração. |
| `name` | `text` | sim | `"CDB Aurora"`. |
| `rate_label` | `text` | sim | `InvestmentProduct.rate`, ex.: `"110% do CDI"`. Texto de exibição. |
| `liquidity_label` | `text` | sim | `InvestmentProduct.liquidity`: `"diária"`, `"D+1"`, `"no vencimento"`, `"D+2"`. |
| `liquidity_days` | `smallint` | sim | Versão numérica: `0`, `1`, `2`. Necessária para agendar o crédito do resgate. |
| `annual_yield` | `numeric(8,6)` | sim | `0.115500` para o CDB. |
| `accent` | `varchar(16)` | sim | Cor no app: `accent`, `blue`, `purple`, `amber`. Apresentação, mas o app espera. |
| `asset_class` | `text` | sim | `RENDA_FIXA`, `FUNDO_IMOBILIARIO`, `TESOURO`. |
| `min_investment` | `numeric(18,2)` | sim | Ausente no app. |
| `maturity_date` | `date` | não | Para LCI/Tesouro. |
| `is_tax_exempt` | `boolean` | sim | LCI é isenta de IR. O app menciona no texto mas não modela. |
| `is_active` | `boolean` | sim | |

### 2.9 `holdings`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | Note: no Swift `Holding.id` é o **id do produto**, não um UUID. A API devolve `product_id`; o app continua chaveando por ele. |
| `user_id` | `uuid` FK → `users` | sim | |
| `product_id` | `varchar(32)` FK → `investment_products` | sim | |
| `account_id` | `uuid` FK → `accounts` | sim | Conta `INVESTMENT` desta posição. |
| `invested` | `numeric(18,2)` | sim | `Holding.invested` — total aportado. |
| `current` | `numeric(18,2)` | sim | `Holding.current` — valor atual com rendimento. |
| `quantity` | `numeric(24,8)` | não | Cotas, para fundos e FII. |
| `last_yield_at` | `date` | não | Última marcação a mercado. |
| `opened_at` | `timestamptz` | sim | |

`UNIQUE (user_id, product_id)`.
`earnings` e `earningsPercent` são derivados no cliente — não persistir.

> **Hoje mockado:** `AppModel.redeem` reduz `invested` proporcionalmente para
> "manter a rentabilidade coerente" e apaga a posição quando zera. O backend
> precisa de contabilidade real: custo médio, IR regressivo por prazo, IOF nos
> primeiros 30 dias, e marcação a mercado diária por job. Nenhuma dessas coisas
> existe hoje.

### 2.10 `goals` (cofrinhos)

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | `Goal.id`. |
| `user_id` | `uuid` FK → `users` | sim | |
| `account_id` | `uuid` FK → `accounts` | sim | Conta `GOAL`. `saved` é o **saldo derivado** desta conta. |
| `name` | `text` | sim | `"Viagem para o Chile"`. |
| `target` | `numeric(18,2)` | sim | `Goal.target`. |
| `symbol` | `varchar(64)` | sim | Nome de SF Symbol: `airplane`, `shield.fill`, `laptopcomputer`. Default `banknote.fill`. |
| `deadline` | `date` | não | `Goal.deadline`. **`DATE`** — é um prazo de calendário. |
| `yields_interest` | `boolean` | sim | Se o cofrinho rende. Default `false`; o app hoje não rende. |
| `archived_at` | `timestamptz` | não | Exclusão é soft — o histórico de lançamentos precisa sobreviver. |

`saved`, `progress`, `percentText`, `isComplete` e `remaining` são derivados.
`saved` **não é coluna**: é o saldo da conta `GOAL`. Ver seção 4, invariante I-3.

### 2.11 `loans`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | `Loan.id`. |
| `user_id` | `uuid` FK → `users` | sim | |
| `liability_account_id` | `uuid` FK → `accounts` | sim | Conta `LOAN_LIABILITY`. |
| `principal` | `numeric(18,2)` | sim | `Loan.principal`. |
| `monthly_rate` | `numeric(8,6)` | sim | `Loan.monthlyRate` — `0.024900` no `LoanFlow`, `0.019900` no parcelamento de fatura. |
| `installment_count` | `smallint` | sim | |
| `installment_amount` | `numeric(18,2)` | sim | PMT da Tabela Price. Ver seção 6.3. |
| `iof_amount` | `numeric(18,2)` | sim | **Ausente no app.** Obrigatório em crédito no Brasil. |
| `cet_annual` | `numeric(8,6)` | sim | Custo Efetivo Total. **Ausente no app.** Exigido pela Resolução CMN 3.517. |
| `origin` | `loan_origin` | sim | `PERSONAL` (`LoanFlow`) ou `INVOICE_INSTALLMENT` (`AppModel.installInvoice`). |
| `origin_invoice_id` | `uuid` FK → `invoices` | não | |
| `state` | `loan_state` | sim | Máquina de estados na seção 5.2. |
| `contracted_at` | `timestamptz` | não | `Loan.contractedAt`. Nulo enquanto simulação. |
| `first_due_date` | `date` | sim | `LoanFlow.firstDueDate()` = hoje + 1 mês. |
| `settled_at` | `timestamptz` | não | |
| `contract_document_url` | `text` | não | CCB assinada. |

`outstanding`, `paidCount`, `nextDue` e `isSettled` são derivados das parcelas.

### 2.12 `installments`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | `Installment.id`. |
| `loan_id` | `uuid` FK → `loans` | sim | |
| `number` | `smallint` | sim | `Installment.number`, 1-based. |
| `total` | `smallint` | sim | `Installment.total`. Redundante com `loans.installment_count`, mas o app usa em `label`. |
| `amount` | `numeric(18,2)` | sim | |
| `principal_portion` | `numeric(18,2)` | sim | Amortização. **Ausente no app.** |
| `interest_portion` | `numeric(18,2)` | sim | Juros. **Ausente no app.** `principal_portion + interest_portion = amount`. |
| `due_date` | `date` | sim | `Installment.dueDate`. **`DATE`** — vencimento é dia de calendário. |
| `paid_at` | `timestamptz` | não | `Installment.paidAt`. |
| `paid_amount` | `numeric(18,2)` | não | Pode diferir de `amount` com juros de mora. |
| `payment_transaction_id` | `uuid` FK → `transactions` | não | |
| `late_fee` | `numeric(18,2)` | sim | Default `0`. |

`UNIQUE (loan_id, number)`. `isPaid` e `isOverdue` são derivados (`isOverdue` usa
`due_date < hoje em America/Sao_Paulo AND paid_at IS NULL`).

Trigger: `UPDATE` rejeitado quando `OLD.paid_at IS NOT NULL` — invariante I-6.

### 2.13 `pix_keys`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | `PixKey.id`. |
| `user_id` | `uuid` FK → `users` | sim | |
| `account_id` | `uuid` FK → `accounts` | sim | |
| `kind` | `pix_key_kind` | sim | `cpf`, `celular`, `email`, `aleatoria` — igual a `PixKey.Kind`. |
| `value` | `text` | sim | Forma canônica DICT: CPF só dígitos, celular E.164, e-mail minúsculo, aleatória UUID v4. |
| `masked` | `text` | sim | `PixKey.masked`, ex.: `***.917.330-**`, `(11) 9****-3120`. **Gerado pelo servidor** — o mascaramento é regra, não decisão do cliente. |
| `state` | `pix_key_state` | sim | `PENDING_CLAIM`, `ACTIVE`, `PORTABILITY_PENDING`, `DELETED`. |
| `dict_registered_at` | `timestamptz` | não | |
| `deleted_at` | `timestamptz` | não | Soft delete — o DICT mantém histórico. |

`UNIQUE (value) WHERE state <> 'DELETED'` — globalmente uma chave pertence a uma conta.
Limite regulatório: 5 chaves por CPF. O app não valida isso hoje.

> **Hoje mockado:** `AppModel.addRandomPixKey()` gera um UUID local e adiciona ao
> array. Não há chamada ao DICT, não há limite de 5 chaves, e `masked` para a
> chave aleatória é o UUID inteiro sem máscara.

### 2.14 `contacts`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | `Contact.id`. |
| `user_id` | `uuid` FK → `users` | sim | |
| `name` | `text` | sim | `Contact.name`. |
| `key` | `text` | sim | `Contact.key` — chave Pix do favorecido, como digitada. |
| `key_kind` | `pix_key_kind` | sim | Inferido pelo servidor. |
| `bank` | `text` | sim | `Contact.bank`, default `"Banco Horizonte"` no mock. Vem da consulta DICT. |
| `bank_ispb` | `char(8)` | não | |
| `document_masked` | `varchar(20)` | não | CPF mascarado do favorecido, como o DICT devolve (`***.917.330-**`). |
| `last_used_at` | `timestamptz` | não | `AppModel.rememberContact` move o contato para o início da lista — a ordenação é por este campo, `DESC NULLS LAST`. |
| `use_count` | `integer` | sim | Default `0`. |

`UNIQUE (user_id, key)` — `rememberContact` já trata duplicata movendo para o topo.

### 2.15 `notifications`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `user_id` | `uuid` FK → `users` | sim | |
| `kind` | `notification_kind` | sim | `transaction`, `security`, `offer`, `bill` — igual a `AppNotification.Kind`. |
| `title` | `text` | sim | `"Pix recebido"`. |
| `message` | `text` | sim | `"R$ 150,00 de João Pedro Lima"`. |
| `deep_link` | `text` | não | Ex.: `aurora://transaction/<id>`. Ausente no app. |
| `related_type` / `related_id` | `text` / `uuid` | não | |
| `read_at` | `timestamptz` | não | Único campo mutável. |
| `sent_push_at` | `timestamptz` | não | |
| `created_at` | `timestamptz` | sim | `AppNotification.date`. |

> **Hoje mockado:** `AppModel.seedNotifications()` devolve quatro notificações
> fixas a cada carregamento, inclusive uma que diz "Score 742 libera análise de
> novo limite". Nada é gerado por evento real.

### 2.16 `devices`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `user_id` | `uuid` FK → `users` | sim | |
| `install_id` | `uuid` | sim | Gerado no primeiro boot, guardado no Keychain. `UNIQUE`. |
| `public_key` | `bytea` | sim | Chave pública P-256 gerada na Secure Enclave. Base das provas de PIN e biometria (seção 7 de `02-api.md`). |
| `key_attestation` | `bytea` | não | App Attest / DeviceCheck. |
| `model` | `text` | sim | `"iPhone 15"`. |
| `os_version` | `text` | sim | |
| `app_version` | `text` | sim | |
| `name` | `text` | não | Nome dado pelo usuário. |
| `biometry_type` | `text` | não | `faceID`, `touchID`, `opticID` — de `LABiometryType`. |
| `status` | `device_status` | sim | `PENDING`, `TRUSTED`, `REVOKED`. |
| `trusted_at` | `timestamptz` | não | |
| `last_seen_at` | `timestamptz` | não | |
| `last_ip` | `inet` | não | |
| `last_city` | `text` | não | `"São Paulo, SP"` — a notificação de segurança do mock cita isso. |

Tabela irmã `device_push_tokens (id, device_id, token, platform, environment, revoked_at)`.

### 2.17 `pin_credentials`

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `user_id` | `uuid` PK FK → `users` | sim | Um PIN por usuário. |
| `hash` | `bytea` | sim | Argon2id. Nunca o PIN, nunca um hash reversível. |
| `salt` | `bytea` | sim | Aleatório por usuário. |
| `params` | `jsonb` | sim | Parâmetros do Argon2 no momento do hash, para rehash progressivo. |
| `failed_attempts` | `smallint` | sim | Default `0`. |
| `locked_until` | `timestamptz` | não | Bloqueio progressivo: 3 erros → 1 min, 5 → 15 min, 7 → bloqueio até suporte. |
| `set_at` | `timestamptz` | sim | |

> **Hoje mockado, e inseguro por construção:** `KeychainSecurityService.hashed()`
> usa FNV-1a com sal fixo `"aurora.salt."`, produzindo 64 bits. Isso é um hash
> não criptográfico sobre um espaço de 10⁴ ou 10⁶ combinações — quebrável
> instantaneamente. O próprio comentário no código reconhece isso. O backend
> precisa de Argon2id e o PIN nunca deve chegar em claro (ver `02-api.md` §7).

### 2.18 `consents` — append-only

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `user_id` | `uuid` FK → `users` | sim | |
| `type` | `consent_type` | sim | `TERMS_OF_USE`, `PRIVACY_POLICY`, `CREDIT_BUREAU_QUERY`, `MARKETING`, `OPEN_FINANCE_SHARING`, `BIOMETRIC_DATA`. |
| `document_version` | `varchar(32)` | sim | Ex.: `2026-03-v4`. |
| `document_hash` | `bytea` | sim | SHA-256 do texto exato aceito. Prova de qual redação foi aceita. |
| `granted` | `boolean` | sim | `false` registra a revogação como novo registro, sem apagar o anterior. |
| `granted_at` | `timestamptz` | sim | |
| `ip` | `inet` | sim | |
| `device_id` | `uuid` FK → `devices` | não | |
| `expires_at` | `timestamptz` | não | Open Finance expira em 12 meses. |

O consentimento vigente é o registro mais recente por `(user_id, type)`.
Revogar não apaga: insere um `granted = false`. Exigência da LGPD art. 9º §2.

### 2.19 `audit_logs` — append-only

| Campo | Tipo SQL | Obrig. | Observação |
|---|---|---|---|
| `id` | `uuid` PK | sim | |
| `sequence` | `bigint` | sim | `BIGSERIAL`, ordem canônica. |
| `actor_type` | `actor_type` | sim | `USER`, `SYSTEM`, `OPERATOR`, `WEBHOOK`. |
| `actor_id` | `uuid` | não | |
| `action` | `text` | sim | `pix.send`, `card.block`, `loan.contract`, `pin.change`. |
| `resource_type` / `resource_id` | `text` / `uuid` | sim / não | |
| `before` / `after` | `jsonb` | não | Diff, com PII já redigida. |
| `ip` | `inet` | não | |
| `device_id` | `uuid` | não | |
| `trace_id` | `text` | sim | Correlaciona com o `trace_id` devolvido nos erros da API. |
| `occurred_at` | `timestamptz` | sim | |
| `prev_hash` / `hash` | `bytea` | sim | Encadeamento: `hash = SHA256(prev_hash || payload)`. Torna adulteração detectável. |

Retenção mínima de 5 anos (Circular BCB 3.978, prevenção à lavagem).

### 2.20 `idempotency_keys`

Detalhada na seção 7.

---

## 3. O modelo de ledger double-entry

### 3.1 Por que o saldo não é uma coluna

O app já acertou a intuição: `Ledger.balance` é
`transactions.reduce(openingBalance) { $0 + $1.amount }`, e o comentário no
código diz exatamente por quê — no protótipo HTML, `balance`, `card.used` e as
categorias de gasto eram campos independentes que saíam de sincronia.

O backend leva isso adiante. Uma coluna `accounts.balance` atualizada por
`UPDATE ... SET balance = balance - 87.40` tem três defeitos fatais:

1. **Não é auditável.** Se o saldo está errado, não há como descobrir qual
   operação errou. Um `UPDATE` apaga a evidência do próprio erro.
2. **Não sobrevive à concorrência.** Dois débitos simultâneos em transações
   concorrentes podem produzir lost update, ou exigir lock pessimista na linha
   da conta — que serializa toda a movimentação do cliente.
3. **Não tem contraparte.** Quando R$ 87,40 saem da conta corrente, entram em
   algum lugar. Saldo-como-coluna não obriga ninguém a dizer onde, e é assim que
   dinheiro "some" em sistemas financeiros.

Saldo derivado resolve os três. A escrita é `INSERT`, que não tem lost update.
A auditoria é a própria tabela. E o double-entry obriga a declarar a contraparte.

### 3.2 Como registrar um débito e um crédito

Toda movimentação é uma `transaction` com N `ledger_entries` somando zero.
`amount` é **sempre positivo**; o sinal vive em `direction`.

**Pix enviado de R$ 60,00 para Ana Luiza Prado** (`PixFlow.commit`, que hoje só
faz `model.ledger.record(tx)` com `amount: -v`):

| `account_id` | `direction` | `amount` |
|---|---|---|
| conta corrente da Marina (`CHECKING`) | `DEBIT` | 60.00 |
| conta de liquidação Pix (interna, `SETTLEMENT`) | `CREDIT` | 60.00 |

Soma algébrica: `-60.00 + 60.00 = 0`. ✅

**Guardar R$ 200,00 no cofrinho "Viagem para o Chile"** (`GoalDepositFlow.commit`,
que hoje faz `model.deposit()` num array e registra uma transação solta):

| `account_id` | `direction` | `amount` |
|---|---|---|
| conta corrente (`CHECKING`) | `DEBIT` | 200.00 |
| conta do cofrinho (`GOAL`) | `CREDIT` | 200.00 |

O dinheiro não sumiu da conta corrente para reaparecer num campo `goal.saved`:
ele **mudou de conta interna**. `Goal.saved` passa a ser o saldo derivado da
conta `GOAL`, e a soma de todas as contas do usuário continua batendo.

**Compra no crédito de R$ 87,40**:

| `account_id` | `direction` | `amount` |
|---|---|---|
| conta de despesa do estabelecimento (interna) | `DEBIT` | 87.40 |
| conta `CARD_LIABILITY` do cartão | `CREDIT` | 87.40 |

A conta corrente **não é tocada** — é exatamente por isso que a fatura existe.
O saldo da `CARD_LIABILITY` é a fatura em aberto, sem varrer string nenhuma.

**Empréstimo de R$ 5.000,00 contratado** (`LoanFlow.commit`):

| `account_id` | `direction` | `amount` |
|---|---|---|
| conta corrente (`CHECKING`) | `CREDIT` | 5000.00 |
| conta `LOAN_LIABILITY` do contrato | `CREDIT` | 5000.00 |
| conta de funding do banco (interna) | `DEBIT` | 10000.00 |

Ou, mais limpo, duas transações separadas: desembolso e reconhecimento da dívida.
O ponto é que a dívida **existe** como saldo. O comentário no Swift já admite o
buraco: "O protótipo creditava o dinheiro e nunca gerava dívida".

**Regra de escrita.** Um único `INSERT ... SELECT` com todas as pernas, dentro de
uma transação SQL `READ COMMITTED`, precedido da validação de saldo. Nada de
duas chamadas. Constraint `DEFERRABLE INITIALLY DEFERRED` sobre a soma zero
(seção 4, I-1) valida no `COMMIT`.

### 3.3 Calcular o saldo

```
saldo(conta) = opening_balance
             + Σ(amount onde direction = 'CREDIT')
             − Σ(amount onde direction = 'DEBIT')
```

Restrito às entries cuja `transaction.state ∈ {AUTHORIZED, SETTLED}`. Transações
`PENDING` contam apenas para o **saldo disponível**, não para o contábil:

- **Saldo contábil**: só `SETTLED`.
- **Saldo disponível**: `SETTLED` + débitos `AUTHORIZED` (uma autorização de
  cartão já comprometeu o dinheiro) − créditos `AUTHORIZED` (ainda não caiu).

O app tem um único `balance`. Ao integrar, `AccountSnapshot` deve trazer os dois;
a validação de `FlowContext.balance` usa o **disponível**.

### 3.4 Snapshot sem perder a derivação

Somar dez anos de lançamentos a cada abertura do app não escala. A saída é um
snapshot que é **cache verificável**, não fonte de verdade.

O truque é o campo `last_sequence`. O saldo fica:

```
saldo = snapshot.balance
      + Σ(entries com sequence > snapshot.last_sequence)
```

Como `sequence` é monotônico e `ledger_entries` é append-only, essa soma é
sempre a mesma coisa que somar tudo desde o início. O snapshot não é uma
verdade paralela — é um resultado parcial memoizado. A propriedade de derivação
sobrevive porque:

1. **O snapshot nunca é escrito por lógica de negócio.** Só por um job que lê o
   ledger. Nenhum endpoint escreve `balance`, como manda o princípio 1 do README.
2. **É reconstruível a qualquer momento.** `DELETE FROM balance_snapshots` e o
   sistema continua correto, só mais lento. Esse é o teste: se apagar o cache
   quebra a correção, não é cache.
3. **É verificado continuamente.** Job diário recalcula do zero e compara com o
   `ROLLING`. Divergência é alerta crítico, não retry silencioso.

Política prática:

| Snapshot | Frequência | Escopo | Imutável? |
|---|---|---|---|
| `ROLLING` | A cada 500 entries ou 1h | Uma linha por conta, sobrescrita | Não |
| `DAILY_CLOSE` | 00:05 America/Sao_Paulo | Uma por conta por dia | Sim |

O `DAILY_CLOSE` serve ao extrato histórico ("saldo no dia 12 de setembro") sem
recomputar nada, e ao fechamento contábil.

**Atualização do `ROLLING`** (idempotente e sem lock de escrita no ledger):

```
UPDATE balance_snapshots
   SET balance  = balance + :delta,
       last_sequence = :max_seq,
       entry_count = entry_count + :n,
       snapshot_at = now()
 WHERE account_id = :id
   AND kind = 'ROLLING'
   AND last_sequence = :prev_max_seq   -- CAS: só avança se ninguém avançou
```

Se o `WHERE` não casar, outro worker já avançou — relê e repete. Sem locks, sem
perda de atualização.

---

## 4. Invariantes do domínio

Cada uma é uma constraint no banco ou um teste de propriedade em CI. Invariante
que só existe em comentário não é invariante.

**I-1 — A soma dos lançamentos de uma transação é zero.**
```
Σ(CREDIT.amount) − Σ(DEBIT.amount) = 0, por transaction_id
```
Constraint `DEFERRABLE INITIALLY DEFERRED` sobre um trigger de agregação, mais
job de varredura contínua. Uma transação com uma perna só nunca deve existir,
nem por um instante visível.

**I-2 — Toda transação tem ao menos duas pernas em contas distintas.**
`COUNT(*) >= 2 AND COUNT(DISTINCT account_id) >= 2`.

**I-3 — Cofrinho nunca fica negativo.**
`saldo(conta GOAL) >= 0`, checado antes do `INSERT` do débito, dentro da mesma
transação SQL, com `SELECT ... FOR UPDATE` na linha do snapshot da conta `GOAL`.
O app já tenta isso em `GoalWithdrawFlow.validate` ("Valor acima do que está
guardado") e em `AppModel.withdraw` com `max(.zero, ...)` — mas o `max` no
cliente **esconde** o erro em vez de impedi-lo. No servidor, é `SALDO_INSUFICIENTE`.

**I-4 — Conta corrente nunca fica negativa sem contrato de cheque especial.**
Mesmo mecanismo. O app valida em todos os `FlowValidation` ("Saldo insuficiente"),
mas validação de cliente é UX, nunca controle (princípio 4 do README).

**I-5 — Fatura = soma das compras de crédito do ciclo, menos pagamentos.**
```
invoice.total_amount = Σ(invoice_items → transactions.amount onde method='credito' e direction=DEBIT)
                     + previous_balance + interest_amount
```
Equivalente ao `Ledger.creditInvoice` do app, mas por ciclo e por `invoice_items`,
não varrendo transações para trás até achar o título `"Pagamento de fatura"`.
Verificação cruzada: `invoice.total_amount − invoice.paid_amount` deve bater com
o saldo da conta `CARD_LIABILITY` para faturas `OPEN`.

**I-6 — Parcela paga é imutável.**
`UPDATE` rejeitado por trigger quando `OLD.paid_at IS NOT NULL`. Corrigir um
pagamento indevido se faz com transação de estorno mais nova parcela, jamais
zerando `paid_at`. O app hoje faz `loans[li].installments[ii].paidAt = .now` em
memória, sem trava alguma.

**I-7 — Parcela tem decomposição consistente.**
`principal_portion + interest_portion = amount` e
`Σ(principal_portion) sobre todas as parcelas = loans.principal` (com tolerância
de ±0,01 na última parcela, onde o arredondamento se acumula).

**I-8 — Empréstimo liquidado tem todas as parcelas pagas.**
`loans.state = 'SETTLED' ⟺ NOT EXISTS (installment WHERE paid_at IS NULL)`.
Equivale ao `Loan.isSettled` do Swift.

**I-9 — Posição de investimento nunca é negativa.**
`holdings.current >= 0 AND holdings.invested >= 0`. Resgate acima do disponível
é `SALDO_INSUFICIENTE`.

**I-10 — `auth_code` é único e imutável.**
`UNIQUE`, e trigger que rejeita alteração. É a chave do comprovante que o cliente
compartilha; mudar significa invalidar um documento já entregue.

**I-11 — Uma compra no crédito pertence a exatamente uma fatura.**
PK composta em `invoice_items` mais `UNIQUE (transaction_id)`.

**I-12 — Chave Pix ativa é globalmente única.**
`UNIQUE (value) WHERE state <> 'DELETED'`, reforçado pelo DICT como autoridade
externa. Máximo de 5 chaves ativas por CPF.

**I-13 — Transação em estado terminal não muda de estado.**
`SETTLED`, `FAILED` e `REVERSED` são absorventes. Estornar cria uma transação
**nova** apontando para a original por `reversed_by_transaction_id`.

**I-14 — Todo lançamento pertence a uma conta do mesmo usuário ou a uma conta
interna do banco.** Impede que um bug misture ledger de clientes diferentes.

**I-15 — A soma de todas as contas do usuário é conservada.**
Movimentações internas (cofrinho, investimento) não criam nem destroem valor:
`Σ saldo(contas do usuário) = patrimônio`. Só transações com contraparte externa
alteram esse total.

---

## 5. Máquinas de estado

### 5.1 Transação

```
                  ┌─────────────┐
                  │   PENDING   │  criada, ainda não comprometeu fundos
                  └──────┬──────┘
             ┌───────────┼───────────┐
             ▼           ▼           ▼
      ┌────────────┐  ┌──────┐  ┌──────────┐
      │ AUTHORIZED │  │FAILED│  │ EXPIRED  │
      └─────┬──────┘  └──────┘  └──────────┘
        ┌───┴────┐       terminal   terminal
        ▼        ▼
   ┌─────────┐ ┌──────┐
   │ SETTLED │ │FAILED│
   └────┬────┘ └──────┘
        ▼
   ┌──────────┐
   │ REVERSED │  terminal (aponta para a transação de estorno)
   └──────────┘
```

| Estado | Significado | Afeta saldo contábil? | Afeta saldo disponível? |
|---|---|---|---|
| `PENDING` | Recebida, em validação (antifraude, limites, DICT) | Não | Não |
| `AUTHORIZED` | Fundos reservados; aguardando liquidação externa | Não | **Sim** |
| `SETTLED` | Liquidada de verdade (SPI confirmou, adquirente capturou) | **Sim** | Sim |
| `FAILED` | Rejeitada; reserva liberada | Não | Não |
| `EXPIRED` | Autorização não capturada no prazo (cartão: 7 dias) | Não | Não |
| `REVERSED` | Estornada por transação nova (MED, chargeback, erro operacional) | Sim (pelo estorno) | Sim |

Transições permitidas e quem as dispara:

| De | Para | Gatilho |
|---|---|---|
| — | `PENDING` | `POST` do cliente com `Idempotency-Key` |
| `PENDING` | `AUTHORIZED` | Validação de saldo, limite e antifraude passou; lançamentos escritos |
| `PENDING` | `FAILED` | `SALDO_INSUFICIENTE`, `LIMITE_*`, antifraude, `CHAVE_PIX_NAO_ENCONTRADA` |
| `AUTHORIZED` | `SETTLED` | Webhook do SPI / captura do adquirente / batch de boleto |
| `AUTHORIZED` | `FAILED` | Rejeição do PSP destino; lançamentos de reversão escritos |
| `AUTHORIZED` | `EXPIRED` | Job de expiração |
| `SETTLED` | `REVERSED` | MED Pix, chargeback de cartão, estorno operacional |

Casos por método:

- **Pix imediato**: `PENDING` → `AUTHORIZED` → `SETTLED` normalmente em segundos.
- **Pix agendado** (`PixFlow.scheduledFor`): fica `PENDING` com `scheduled_for`
  no futuro; o job de agendamento revalida saldo no dia e só então autoriza.
  Se faltar saldo na data, vai a `FAILED` com notificação.
- **Débito**: `AUTHORIZED` na autorização, `SETTLED` na captura (D+1).
- **Crédito**: `AUTHORIZED` na compra, `SETTLED` na captura; não mexe em conta
  corrente, mexe em `CARD_LIABILITY`.
- **Boleto**: `AUTHORIZED` ao debitar, `SETTLED` na confirmação do arquivo de
  retorno (pode levar até D+1). O app hoje trata como instantâneo.

> **Hoje mockado:** nenhum estado existe. `Ledger.record(tx)` insere direto e
> pronto — toda transação nasce liquidada. O app precisa ganhar o campo `state`
> e mostrar "processando" quando for `PENDING`/`AUTHORIZED`.

### 5.2 Empréstimo

```
SIMULATED ──> OFFERED ──> SIGNED ──> DISBURSED ──> ACTIVE ──┬──> SETTLED
    │            │                                          │
    └──> EXPIRED └──> REJECTED                               ├──> DELINQUENT ──> ACTIVE
                                                             │        │
                                                             │        └──> WRITTEN_OFF
                                                             └──> RENEGOTIATED
```

| Estado | Significado |
|---|---|
| `SIMULATED` | Simulação feita; sem compromisso. TTL de 7 dias. |
| `OFFERED` | Proposta formal com CET e IOF calculados; taxa travada por 48h. |
| `REJECTED` | Análise de crédito recusou. |
| `EXPIRED` | Oferta não aceita no prazo. |
| `SIGNED` | CCB assinada eletronicamente; parcelas geradas. |
| `DISBURSED` | Principal creditado na conta corrente; `LOAN_LIABILITY` criada. |
| `ACTIVE` | Em pagamento; ao menos uma parcela em aberto. |
| `DELINQUENT` | Parcela vencida há mais de 5 dias. Encargos correm. |
| `RENEGOTIATED` | Substituído por novo contrato. |
| `WRITTEN_OFF` | Baixado como prejuízo (após 180 dias). |
| `SETTLED` | Todas as parcelas pagas — `Loan.isSettled`. |

`DELINQUENT → ACTIVE` ao regularizar. `SETTLED` e `WRITTEN_OFF` são terminais.

> **Hoje mockado:** `AppModel.contractLoan` pula direto de nada para o
> equivalente a `ACTIVE`: gera o cronograma e credita o dinheiro na mesma
> chamada síncrona. Não há análise de crédito, assinatura, CET, IOF nem
> inadimplência. `AppModel.installInvoice` faz pior: contrata um empréstimo a
> 1,99% a.m. sem passar por nenhuma análise.

---

## 6. Regras de cálculo que o backend precisa reproduzir

### 6.1 Fatura em aberto

O app faz (`Ledger.creditInvoice`): varre transações da mais recente para a mais
antiga, para ao encontrar `title == "Pagamento de fatura"`, e soma os débitos com
`method == .credito` no caminho.

O backend faz: soma os `invoice_items` da fatura `OPEN` do cartão. Resultado
equivalente para o caso feliz, correto para os casos que o app erra — pagamento
parcial, mais de um cartão, compra lançada com data retroativa, estorno.

`availableCardLimit` (`AppModel`) = `credit_limit − saldo(CARD_LIABILITY)`,
com `temporary_limit` somado enquanto vigente.

### 6.2 Orçamento e gastos por categoria

`Ledger.spending(in:)` filtra débitos com `category.isSpending` no período,
agrupa por categoria, e calcula `ratio = total / maior total`. O `ratio` é
apresentação — a API devolve os totais e o app calcula a largura da barra.

`monthSpending` usa `DateInterval.currentMonth`, que no Swift é o mês corrente no
fuso do dispositivo. No servidor, é o mês corrente em `America/Sao_Paulo`
(seção 9). `budgetRemaining = max(0, monthly_budget − monthSpending)`.

### 6.3 Parcela de empréstimo — Tabela Price

O app implementa em `Loan.payment`:

```
PMT = PV · i / (1 − (1+i)^−n)
```

`LoanFlow` usa `i = 0.0249` a.m.; `AppModel.installInvoice` usa `0.0199` a.m.

Duas divergências a corrigir no backend:

1. **`Loan.payment` converte para `Double` para usar `pow`**, e só depois volta
   para `Decimal` com `.rounded(2)`. Contradiz o princípio 2 do README. O backend
   deve usar aritmética decimal de precisão arbitrária e arredondar só no fim.
2. **O arredondamento sobra.** `PMT × n` raramente é igual ao total devido. A
   convenção: arredondar cada parcela para cima em 2 casas e jogar a diferença
   acumulada na **última** parcela, de modo que `Σ parcelas` bata exatamente com
   principal + juros + IOF. O app não trata isso.

A parcela precisa ainda de decomposição (I-7), IOF e CET, todos ausentes no app.

### 6.4 Limite noturno

`FlowContext.isNight()`: hora local `>= 20 || < 6`. Se `nightLimitEnabled` e é
noite e valor `> nightLimit` (default R$ 1.000), o Pix é barrado.

No backend: janela em `America/Sao_Paulo`, não no fuso do device — senão um
cliente viajando ao exterior burla a regra mudando o relógio. Regulação do BCB
sobre limite noturno Pix (20h–6h) é obrigatória, não opcional como o toggle
`nightLimitEnabled` sugere: o toggle ajusta o valor dentro de um teto imposto
pelo banco, não desliga o controle.

---

## 7. Idempotência

Princípio 3 do README: "a rede móvel cai no meio de um Pix e o retry não pode
duplicar a transação". Sem isso, um `POST /v1/pix/payments` reenviado é um
segundo Pix.

### Tabela

```
idempotency_keys
  id                 uuid PK
  user_id            uuid NOT NULL FK → users
  key                text NOT NULL          -- valor do header Idempotency-Key
  endpoint           text NOT NULL          -- "POST /v1/pix/payments"
  request_hash       bytea NOT NULL         -- SHA-256 do corpo canonicalizado
  state              idem_state NOT NULL    -- IN_PROGRESS | COMPLETED | FAILED
  response_status    smallint
  response_body      jsonb
  resource_type      text
  resource_id        uuid
  locked_at          timestamptz
  completed_at       timestamptz
  expires_at         timestamptz NOT NULL
  created_at         timestamptz NOT NULL

  UNIQUE (user_id, endpoint, key)
```

### Escopo

`(user_id, endpoint, key)`. **Não global**, por três razões: a mesma chave gerada
por dois clientes diferentes não deve colidir; incluir `endpoint` impede que um
retry de um endpoint seja atendido pela resposta de outro; e o escopo por usuário
impede que a chave de um cliente vaze informação sobre outro.

A chave é gerada pelo **cliente** — UUID v4 por intenção do usuário, não por
tentativa HTTP. Todas as retentativas do mesmo Pix carregam a mesma chave. Se o
usuário voltar e refizer o fluxo, é uma nova intenção e uma nova chave.

No app, cada `FlowSession` deve gerar sua chave ao entrar no passo `.pin` e
reusá-la em todas as retentativas do `commit`.

### TTL

**24 horas** (`expires_at = created_at + interval '24 hours'`). Cobre com folga
qualquer retry razoável de cliente móvel, inclusive app fechado e reaberto no dia
seguinte. Purge diário das expiradas.

Exceção: chaves que resultaram em transação `PENDING`/`AUTHORIZED` retêm por
**7 dias**, para que o cliente possa reconsultar o resultado de uma operação que
ainda estava se liquidando quando a chave normal expiraria.

### Algoritmo

1. `INSERT ... ON CONFLICT (user_id, endpoint, key) DO NOTHING` com
   `state = 'IN_PROGRESS'` e `locked_at = now()`.
2. **Inseriu** → é a primeira vez. Processa, e ao final grava `state`,
   `response_status`, `response_body` na mesma transação SQL da escrita de
   negócio. Atomicidade aqui é o que garante que não existe "processou mas não
   registrou".
3. **Não inseriu** → já existe. Três casos:
   - `COMPLETED` e `request_hash` bate → devolve a resposta gravada, com
     `Idempotent-Replay: true`. Status idêntico ao original.
   - `COMPLETED` e `request_hash` **não** bate → `409` com
     `IDEMPOTENCY_KEY_REUTILIZADA`. Mesma chave, corpo diferente, é bug de
     cliente e pode ser ataque.
   - `IN_PROGRESS` → `409` com `REQUISICAO_EM_ANDAMENTO` e `Retry-After: 2`. Se
     `locked_at` tem mais de 60s, um job marca como `FAILED` e libera (o processo
     original morreu).

### Onde é obrigatório

Todo `POST`, `PUT`, `PATCH` e `DELETE`. Requisição de escrita sem
`Idempotency-Key` recebe `400 IDEMPOTENCY_KEY_AUSENTE`. `GET` e `HEAD` são
idempotentes por definição HTTP e não usam o header.

---

## 8. Precisão monetária

**No banco:** `NUMERIC(18,2)`. Nunca `float`, `real` ou `double precision`.
18 dígitos comportam R$ 9.999.999.999.999.999,99 — folgado para uma conta PF e
suficiente para totais agregados.

**No transporte (JSON):** inteiro de centavos, com a moeda ao lado.

```json
{ "amount": 8740, "currency": "BRL" }
```

Nunca `87.40`, e nunca `"87.40"`. `87.40` em JSON é IEEE-754 binário e não tem
representação exata; um parser JavaScript lê `87.40000000000001`. Centavos como
inteiro é exato em qualquer linguagem, e `Money(cents:)` já existe no Swift
exatamente para isso.

O app já está preparado: `Money.cents` serializa e `Money(cents:)` desserializa.
O que falta é o `Codable` de `Money` — hoje ele codifica o `Decimal` cru,
o que gera `{"amount": 87.4}`. **Precisa mudar para centavos inteiros** antes da
integração.

**Na memória do servidor:** `BigDecimal` (JVM), `decimal.Decimal` (Python),
`decimal.Decimal`/`pgtype.Numeric` (Go), `Prisma.Decimal` (Node). Jamais o tipo
`number` nativo do JavaScript para valores monetários.

**Arredondamento:** meio-para-cima (`ROUND_HALF_UP`) em 2 casas, aplicado uma
única vez no fim do cálculo. Nunca arredondar parciais e somar. Onde a divisão
não fecha (rateio de parcelas, divisão de IOF), a sobra vai para a última fração
— e existe um teste que verifica que a soma das partes é igual ao todo.

**Taxas e percentuais** são `NUMERIC(8,6)`, não dinheiro: `0.024900` para
2,49% a.m. Guardar taxa como float introduz erro que se propaga por 36 parcelas.

**Cotas de investimento** são `NUMERIC(24,8)` — 8 casas é o padrão de mercado
para cotas de fundo.

---

## 9. Fusos horários e datas

**Regra geral: armazenar em UTC, exibir em `America/Sao_Paulo`.**

Todo `TIMESTAMPTZ` no PostgreSQL. A sessão da aplicação roda com `SET TIME ZONE
'UTC'` para que nenhum resultado dependa da configuração do servidor. A API
sempre serializa em ISO 8601 com `Z`:

```json
{ "occurred_at": "2026-09-26T15:32:10Z" }
```

O app converte para o fuso do dispositivo na exibição — o que já faz via
`DateFormatter` com `Locale(identifier: "pt_BR")` em `TransactionGroup.title` e
`PixFlow.dateText`.

**Datas de vencimento são `DATE`, não `TIMESTAMPTZ`.** Um boleto que vence em
10 de outubro vence no dia 10 em São Paulo, ponto. Guardar como timestamp cria
o bug clássico: `2026-10-10T00:00:00-03:00` vira `2026-10-10T03:00:00Z`, que num
servidor configurado em UTC se exibe como dia 10, mas num cliente em Lisboa
(UTC+1) vira dia 10 às 4h — e se o horário fosse 23h, viraria dia 11.

Campos que são `DATE`:

| Campo | Tabela |
|---|---|
| `due_date` | `invoices`, `installments` |
| `deadline` | `goals` |
| `first_due_date` | `loans` |
| `cycle_start`, `cycle_end`, `reference_month` | `invoices` |
| `effective_date` | `ledger_entries` |
| `maturity_date` | `investment_products` |
| `birth_date` | `users` |
| `temporary_limit_until` | `cards` |

Campos que são `TIMESTAMPTZ`: `occurred_at`, `settled_at`, `paid_at`,
`scheduled_for`, `created_at`, `posted_at`, e todo `*_at`.

O app hoje usa `Date` (que é um instante) para `Installment.dueDate` e
`Goal.deadline`. Na integração, esses campos devem virar `DateComponents` ou uma
struct `CalendarDate`, e a API deve serializá-los como `"2026-10-10"`, não como
timestamp.

**Fronteiras de dia são calculadas em `America/Sao_Paulo`.** "Gastos deste mês",
"extrato de hoje", "limite noturno 20h–6h" e "parcela vencida" são todos
conceitos de calendário brasileiro. `DateInterval.currentMonth` no Swift usa
`Calendar.current`, que é o fuso do device — o servidor **não** pode replicar
isso, ou um cliente em outro fuso veria um mês diferente e poderia burlar o
limite noturno.

**Horário de verão:** o Brasil não observa DST desde 2019, mas
`America/Sao_Paulo` na tzdata carrega o histórico. Usar sempre o nome do fuso,
nunca o offset fixo `-03:00`, para que datas históricas anteriores a 2019
continuem corretas no extrato.

**Dias úteis:** liquidação de TED, D+1 de investimento e vencimento de boleto
respeitam o calendário de feriados bancários da ANBIMA. Tabela `bank_holidays
(date PK, name, scope)` mantida anualmente. Quando um vencimento cai em dia não
útil, o pagamento é aceito no próximo dia útil sem encargos. O app não tem
nenhuma noção disso.

---

## 10. Resumo das lacunas entre app e backend

Tudo que o app simula e o backend terá de fazer de verdade:

| Área | O que o app faz hoje | O que o backend precisa fazer |
|---|---|---|
| Saldo | `Ledger.balance` soma um array em memória | Derivar do ledger double-entry com snapshot |
| Cofrinho | Campo `goal.saved` mutado direto | Conta interna `GOAL` com lançamentos |
| Investimento | `holdings[i].current += amount` | Cotas, custo médio, IR regressivo, IOF, marcação a mercado |
| Fatura | Varre transações até achar a string `"Pagamento de fatura"` | Ciclos, `invoice_items`, rotativo, mínimo |
| Cartão | PAN e CVV literais no struct `Card` | Tokenização PCI-DSS; PAN nunca no banco |
| Empréstimo | Credita e gera parcelas na hora | Análise de crédito, CET, IOF, CCB, inadimplência |
| PIN | FNV-1a com sal fixo, 64 bits, no device | Argon2id no servidor, PIN nunca em claro |
| `authCode` | 31 hex aleatórios gerados no cliente | `endToEndId` do SPI |
| Chave Pix | `UUID()` local, sem limite | Registro no DICT, máximo de 5, portabilidade |
| Boleto | `MockData.boleto()` escolhe de 4 presets pelo hash do código | Consulta real por linha digitável |
| Recarga | `MockData.carrier()` sorteia entre 4 operadoras pelo hash | Integração com operadora |
| Score | Constante `742` | Bureau + modelo interno, com histórico |
| Notificações | 4 itens fixos recriados a cada `load()` | Geração por evento, push real |
| Estado de transação | Inexistente — tudo nasce liquidado | `PENDING`/`AUTHORIZED`/`SETTLED`/`FAILED`/`REVERSED` |
| Idempotência | Inexistente | Tabela de chaves com TTL e replay |
| Auditoria | Inexistente | `audit_logs` encadeado por hash, 5 anos |
| Consentimento | Inexistente | `consents` versionado, LGPD |
| Serialização de `Money` | `Decimal` cru no `Codable` | Centavos inteiros |

---

Contrato da API que expõe este domínio: [02-api.md](02-api.md).

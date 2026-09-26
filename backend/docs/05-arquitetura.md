# Arquitetura — Aurora Bank Sandbox

> **Decisões tomadas:** Java 21 + Spring Boot, PostgreSQL.
> **Natureza do produto:** banco *sandbox*, não banco de produção.

Este documento existe para ser discutido antes de escrever código. Ele
recomenda um desenho e explica o porquê de cada escolha — inclusive das
coisas que deliberadamente **não** vamos fazer.

---

## 1. O que muda por ser um sandbox

Essa é a decisão mais consequente do projeto, e ela não é um detalhe de
configuração: ela atravessa o domínio inteiro.

Um banco de produção e um banco sandbox têm requisitos **diferentes**, não
requisitos "menores". Colocando lado a lado:

| Dimensão | Banco de produção | Banco sandbox |
|---|---|---|
| **Tempo** | Corre sozinho. `now()` é a verdade. | **Controlável.** Quem testa precisa de "avance 30 dias e feche a fatura" sem esperar 30 dias. |
| **Determinismo** | Irrelevante; cada execução é única. | **Essencial.** O mesmo roteiro tem de produzir o mesmo resultado, sempre. |
| **Reset** | Impensável. | **Requisito de primeira classe.** Voltar ao estado inicial em um comando. |
| **Dados** | Reais, sigilosos, LGPD. | Sintéticos, mas **realistas** o bastante para expor bugs. |
| **Contrapartes** | SPI/Bacen, bandeiras, bureaus. | **Simuladores** que reproduzem latência, recusa e falha. |
| **Falhas** | A evitar a todo custo. | A **provocar sob demanda** — testar o caminho triste é o ponto. |
| **Escala** | Milhões de contas. | Dezenas. Otimizar para isso é desperdício. |
| **Auditoria** | Exigência regulatória. | Ferramenta didática: mostrar *por que* o saldo é o que é. |

**A conclusão prática:** o rigor contábil dos documentos 01 e 02 continua
valendo integralmente — double-entry, saldo derivado, invariantes, idempotência.
Isso não é over-engineering; é o que faz o sandbox ensinar a coisa certa. O que
sai são as preocupações de **escala e disponibilidade**: nada de sharding, filas
distribuídas, multi-região, cache distribuído. O que **entra**, e não estava
previsto, são as quatro capacidades da tabela acima: relógio, determinismo,
reset e simuladores de falha.

### 1.1 O relógio é parte do domínio

Se houver uma única recomendação para levar deste documento, é esta.

Nenhuma linha de código de negócio chama `Instant.now()`, `LocalDate.now()` ou
`new Date()`. Todas recebem um `Clock` injetado. O Java já tem isso na
biblioteca padrão (`java.time.Clock`), e o Spring injeta como qualquer bean.

```java
// Errado — impossível de testar, impossível de simular.
if (installment.dueDate().isBefore(LocalDate.now())) { ... }

// Certo — o tempo é uma dependência como qualquer outra.
if (installment.dueDate().isBefore(LocalDate.now(clock))) { ... }
```

No sandbox esse bean é um `MutableClock` por tenant, com endpoints de controle:

```
POST /v1/sandbox/clock/advance   { "duration": "P30D" }
POST /v1/sandbox/clock/set       { "instant": "2026-12-31T23:59:00Z" }
POST /v1/sandbox/clock/reset
```

Avançar o relógio **dispara os jobs que teriam rodado** naquele intervalo:
vencimento de parcela, fechamento de fatura, crédito de rendimento, liquidação
de Pix agendado. É isso que transforma o sandbox em algo útil — dá para ver o
mês inteiro acontecer em dois segundos.

Isso precisa estar no primeiro commit. Enxertar `Clock` depois significa
revisitar cada arquivo do domínio, e na prática significa nunca fazer.

> **Consequência para os docs existentes:** o `01-dominio.md` usa
> `DEFAULT now()` em várias tabelas. Num sandbox com relógio controlável, o
> default do banco mente. As colunas de tempo de negócio (`contracted_at`,
> `due_date`, `paid_at`, `date` da transação) têm de vir da aplicação, com o
> clock injetado. Só as colunas de auditoria física (`created_at` de log)
> podem usar o relógio real — e é bom que usem, para diferenciar "quando
> aconteceu no mundo simulado" de "quando foi gravado de verdade".

### 1.2 Determinismo e reset

Toda fonte de aleatoriedade vira dependência injetada, pelo mesmo motivo do
relógio: `Random` com semente fixa por tenant, e geração de ids (`authCode` do
Pix, por exemplo) derivada dessa semente. O app hoje gera `authCode` no
dispositivo com `Int.random` — isso passa para o servidor e vira determinístico.

Reset tem duas formas, e vale ter as duas:

- **`POST /v1/sandbox/reset`** — trunca os dados do tenant e recarrega o
  *seed*. Rápido, é o que se usa entre testes.
- **Snapshot/restore nomeado** — salva o estado atual sob um rótulo e volta
  a ele depois. Útil para montar cenários ("conta com fatura vencida e
  empréstimo em atraso") e reusar.

### 1.3 Multi-tenant leve

Cada consumidor do sandbox precisa do seu próprio mundo isolado: seu relógio,
sua semente, seus dados. Sem isso, um teste que avança 30 dias quebra o teste
de outra pessoa.

A forma mais simples que funciona: **uma coluna `tenant_id` em toda tabela** e
Row Level Security do Postgres para garantir o isolamento no banco, não só na
aplicação. Não precisa de schema por tenant nem banco por tenant nessa escala —
seria complexidade sem retorno.

---

## 2. Arquitetura da aplicação

### 2.1 Forma geral: modular monolith

**Recomendação: um único deployable, com módulos de fronteira explícita.**

Microsserviços aqui seriam um erro caro. O domínio é fortemente transacional —
um Pix toca conta, ledger, limites e notificação, e tudo isso precisa de uma
transação ACID. Distribuir isso troca um `@Transactional` que funciona por
sagas, compensações e consistência eventual, para resolver um problema de
escala que o sandbox não tem.

O monolito modular dá a separação conceitual sem o custo distribuído, e deixa
a porta aberta: se um módulo um dia precisar sair, a fronteira já existe.

```
br.com.aurora
├── shared/           tipos comuns: Money, Clock, ids, erros, idempotência
├── ledger/           ★ núcleo contábil — não depende de ninguém
├── accounts/         conta, snapshot inicial, extrato
├── identity/         usuário, onboarding, KYC, device, PIN, sessão
├── pix/              chaves, envio, cobrança, agendamento, devolução
├── payments/         boleto, recarga, tributos
├── cards/            cartão, fatura, parcelamento, autorização
├── credit/           score, simulação, contrato, parcelas
├── investments/      produtos, posições, aplicação, resgate, rendimento
├── goals/            cofrinhos
├── notifications/    central de mensagens, push
├── support/          chamados, FAQ
└── sandbox/          ★ relógio, seed, reset, simuladores, caos
```

Duas regras de dependência, e só:

1. **`ledger` não depende de nenhum módulo de negócio.** Ele não sabe o que é
   Pix ou cartão — só sabe debitar e creditar contas. Os módulos de negócio
   dependem dele.
2. **Módulos de negócio não se chamam diretamente.** Conversam por eventos de
   domínio internos (`ApplicationEventPublisher` do Spring) ou por uma porta
   explícita. `pix` não importa classe de `notifications`; ele publica
   `PixLiquidado` e quem quiser que escute.

Isso se verifica em CI com ArchUnit — regra de arquitetura que não é testada
vira decoração.

### 2.2 Dentro de cada módulo: hexagonal, com parcimônia

```
pix/
├── domain/          entidades e regras. Zero import de Spring, zero de JPA.
├── application/     casos de uso. Orquestra domínio + portas. @Transactional aqui.
├── ports/           interfaces do que o módulo precisa do mundo (DICT, SPI)
└── adapters/
    ├── rest/        controllers, DTOs
    ├── persistence/ repositórios JPA, entidades de banco
    └── external/    implementações das portas (simulador no sandbox)
```

O ganho concreto disso aqui não é purismo: é que **o simulador do SPI e o
cliente real do SPI implementam a mesma porta**. Trocar um pelo outro é mudar
qual bean está ativo, e o domínio nunca fica sabendo.

Onde ser parcimonioso: não criar as quatro camadas para módulos triviais.
`support` não precisa de hexagonal. A estrutura completa se justifica em
`ledger`, `pix`, `cards` e `credit`.

### 2.3 Domínio rico, não anêmico

O documento 01 define invariantes de verdade (soma zero, cofrinho não-negativo,
parcela paga imutável). Elas têm de viver em objetos que as protegem, não em
services que as verificam por cortesia.

```java
// Money é value object com Decimal — nunca double, nunca BigDecimal solto.
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount);
        if (amount.scale() > 2) amount = amount.setScale(2, RoundingMode.HALF_EVEN);
    }
    public Money plus(Money o) { requireSameCurrency(o); return new Money(amount.add(o.amount), currency); }
}

// Uma transação de ledger não pode ser construída desbalanceada.
public final class LedgerTransaction {
    private LedgerTransaction(List<Entry> entries) { ... }

    public static LedgerTransaction of(List<Entry> entries) {
        if (entries.size() < 2) throw new DomainException(PERNAS_INSUFICIENTES);
        if (!sumsToZero(entries)) throw new DomainException(LANCAMENTO_DESBALANCEADO);
        return new LedgerTransaction(entries);
    }
}
```

A invariante I-1 do documento 01 fica garantida em **três camadas**: o
construtor recusa, a constraint `DEFERRABLE` do Postgres recusa, e o job de
varredura acusa. Redundância aqui é barata e o erro é caro.

Java 21 ajuda bastante: `record` para value objects, `sealed interface` para
estados (`sealed interface TransactionState permits Pending, Authorized, ...`)
com pattern matching exaustivo checado pelo compilador — que é exatamente o que
se quer para as máquinas de estado da seção 5 do documento 01.

### 2.4 Persistência

- **Flyway** para migrations, versionadas desde a primeira.
- **JPA/Hibernate** para o CRUD comum; **JdbcTemplate ou jOOQ** para o ledger.
  O ledger tem queries de agregação e um `INSERT ... SELECT` multi-perna que
  em JPA ficam piores do que em SQL direto. Misturar os dois é pragmático, não
  incoerente — cada um onde rende.
- **`DECIMAL(18,2)`** para dinheiro, sempre. Nunca `double`, nunca `float`.
- **Testcontainers** para testar contra Postgres real. H2 mente sobre
  constraints deferidas e sobre tipos — e são exatamente essas as garantias
  que mais importam aqui.

### 2.5 A fronteira HTTP

O documento 02 já especifica o contrato. O que a arquitetura acrescenta:

- **OpenAPI gerado do código** (springdoc), não escrito à mão, para não
  divergir. O sandbox publica o Swagger UI — é a cara do produto para quem
  integra.
- **`@RestControllerAdvice` único** traduzindo `DomainException` no formato de
  erro do documento 02. Nenhum controller monta erro na mão.
- **Idempotência como filtro**, não como código repetido em cada handler. Um
  interceptor lê `Idempotency-Key`, consulta a tabela, e devolve a resposta
  gravada se já existir.
- **`aal` (authentication assurance level)** como o documento 02 define,
  verificado por anotação no caso de uso.

---

## 3. Os simuladores: o coração do sandbox

Num banco real, isso seriam integrações. Aqui **são o produto**. Merecem
desenho de primeira classe, não mocks jogados no fim.

Cada contraparte externa é uma porta com implementação simulada configurável:

| Porta | Simula | Configurável |
|---|---|---|
| `DictPort` | Diretório de chaves Pix | Chave existe? De qual banco? Latência? |
| `SpiPort` | Liquidação Pix no Bacen | Liquida, recusa, demora, cai |
| `BoletoPort` | Registro e baixa de boleto | Válido, vencido, já pago |
| `CardNetworkPort` | Autorização de cartão | Aprova, nega, timeout, chargeback |
| `BureauPort` | Score de crédito | Faixa de score, negativação |
| `PushPort` | Envio de push | Entrega, falha |

E um **painel de caos** que é o que diferencia um sandbox bom de um medíocre:

```
POST /v1/sandbox/chaos
{
  "port": "SpiPort",
  "behavior": "REJECT",
  "reason": "SALDO_INSUFICIENTE_NO_PSP",
  "applies_to_next": 1
}
```

Sem isso, quem integra só testa o caminho feliz — e o caminho feliz não é onde
os bugs moram. É justamente por isso que o app iOS hoje tem tantos toasts no
lugar de fluxos: nunca houve um servidor para dizer "não".

---

## 4. O que **não** fazer

Lista tão importante quanto a das recomendações, porque a tentação é real:

| Não fazer | Por quê |
|---|---|
| Microsserviços | Domínio transacional; sagas resolveriam um problema inexistente. |
| Kafka / mensageria distribuída | Eventos do Spring bastam nesta escala. Kafka é operação, não arquitetura. |
| Redis / cache distribuído | Dezenas de contas. O Postgres dá conta com folga. |
| CQRS com bancos separados | Complexidade alta, ganho zero aqui. Views materializadas resolvem. |
| Event Sourcing completo | O ledger append-only já entrega auditoria e replay, sem o custo do ES. |
| Kubernetes desde o dia 1 | Um contêiner e um Postgres. Docker Compose basta. |
| GraphQL | O documento 02 já é REST e o app já foi desenhado para ele. |
| Fazer o app falar direto com o banco | Óbvio, mas registrado. |

O critério que unifica a lista: **cada peça de infraestrutura tem de pagar seu
custo de operação com um problema real e presente.** Num sandbox, quase nenhuma
paga.

---

## 5. Ordem de construção sugerida

Uma vez fechada a arquitetura, esta é a sequência que eu defenderia — cada fase
entrega algo demonstrável e nenhuma gera retrabalho na seguinte:

| Fase | Entrega | Por que nesta ordem |
|---|---|---|
| **0. Esqueleto** | Spring Boot, Flyway, Testcontainers, Docker Compose, `Money`, `Clock` injetado, formato de erro, ArchUnit | O `Clock` e o `Money` entram antes de qualquer regra. Depois é tarde. |
| **1. Ledger** | Contas internas, lançamentos, invariantes, snapshot, idempotência | Núcleo do qual tudo depende. Testado com property-based: mil operações aleatórias, soma sempre zero. |
| **2. Sandbox** | Relógio controlável, seed, reset, multi-tenant | Entra cedo porque as fases seguintes já nascem testáveis com viagem no tempo. |
| **3. Identidade** | Onboarding, KYC simulado, device, PIN com challenge, JWT | Primeiro contato do app com o servidor de verdade. |
| **4. Conta e extrato** | Snapshot inicial, saldo, extrato com filtros, comprovante | Substitui o `MockAccountService` do app. Primeira integração ponta a ponta. |
| **5. Pix** | Chaves, DICT simulado, envio, cobrança, agendado, devolução | Fluxo mais usado; exercita ledger, limites, idempotência e simulador. |
| **6. Cartões** | Autorização, fatura derivada, pagamento, parcelamento | Fecha a maior lacuna do protótipo: fatura que não acumulava. |
| **7. Crédito** | Score, simulação, contrato com parcelas, pagamento | Fecha o buraco do empréstimo sem dívida. |
| **8. Investimentos e cofrinhos** | Produtos, aplicação, resgate, rendimento por job no relógio | Rendimento fica visível ao avançar o relógio — vitrine do sandbox. |
| **9. Notificações e suporte** | Central, push simulado, chamados | Completa as categorias ausentes. |

**A fase 4 é o marco que vale perseguir:** é quando o app iOS deixa de ser
mockado e passa a falar com um servidor real. Tudo antes é fundação; tudo
depois é expansão sobre trilhos já assentados.

---

## 6. Perguntas em aberto para decidir

1. **Um sandbox público ou privado?** Se outras pessoas vão integrar, precisa
   de cadastro de aplicação, chaves de API e rate limit — o que muda a fase 3.
2. **O relógio é por tenant ou global?** Por tenant é mais correto e só um
   pouco mais caro. Recomendo por tenant.
3. **Quão fundo vai o realismo do Pix?** Reproduzir as mensagens ISO 20022 do
   SPI é excelente para quem quer aprender o protocolo de verdade, mas é um
   projeto em si. Dá para começar com uma abstração mais simples e aprofundar.
4. **Haverá console web?** Um painel para mexer no relógio, ver o ledger e
   provocar falhas multiplica o valor do sandbox — e é onde o design system que
   você está redesenhando renderia duas vezes.

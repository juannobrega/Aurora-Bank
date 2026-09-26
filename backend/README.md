# Aurora Bank — Backend

Documentação do que o backend precisa ter para sustentar o app iOS.

Estes documentos são escritos **a partir do domínio já modelado no app**
(`IOS APP/Aurora/Aurora/Models`), para que cliente e servidor não divirjam.
Enquanto o backend não existe, o app roda com `MockAccountService`, que
implementa o protocolo `AccountServicing` — a troca para rede não deve
exigir mudança em nenhuma view.

## Índice

| Documento | Conteúdo |
|---|---|
| [docs/01-dominio.md](docs/01-dominio.md) | Entidades, invariantes e o modelo de ledger |
| [docs/02-api.md](docs/02-api.md) | Contrato REST: endpoints, payloads, erros |
| [docs/03-seguranca.md](docs/03-seguranca.md) | Autenticação, device binding, PIN, antifraude, LGPD |
| [docs/04-integracoes.md](docs/04-integracoes.md) | Pix/SPI, boletos, cartões, Open Finance |
| [docs/05-arquitetura.md](docs/05-arquitetura.md) | Stack, serviços, dados, observabilidade |
| [docs/06-roadmap.md](docs/06-roadmap.md) | Ordem de construção alinhada às fases do app |

## Como rodar

Tudo sobe em contêiner — banco e API:

```bash
docker compose up --build        # sobe db + api
# API em http://localhost:8080/docs
```

Para desenvolver com recarga rápida, sobe só o banco e roda a API local:

```bash
docker compose up -d db
mvn spring-boot:run
```

Testes de domínio não precisam de banco:

```bash
mvn test
```

### Teste de ponta a ponta

Com a stack no ar, `scripts/e2e.sh` percorre a API inteira: cria conta,
valida rosto, entra por PIN e por biometria, tenta entrar como impostor,
contrata empréstimo, envia Pix, usa cofrinho, investe, compra no cartão,
paga fatura e parcela, e confere que o aparelho continua vinculado após
o logout.

```bash
docker compose up -d --build
./scripts/e2e.sh
```

### Verificação das invariantes do razão

As invariantes I-1 (soma zero), I-2 (duas pernas em contas distintas),
append-only e valor positivo são garantidas **no banco**, não só em Java.
Para conferir:

```bash
docker compose up -d db
docker compose exec -T db psql -U aurora -d aurora \
  < src/main/resources/db/migration/V1__ledger_core.sql
docker compose exec -T db psql -U aurora -d aurora < scripts/verify-ledger.sql
```

Os blocos T3 a T7 **devem** falhar com erro — é isso que prova que a
garantia existe. T2 deve mostrar 6200.00 e T8 deve mostrar 0.00.

> **Nota sobre Testcontainers.** Existe um `LedgerPersistenceTest` escrito,
> mas ele não roda neste ambiente: o Docker Desktop 29 exige API >= 1.44 e
> o cliente docker-java empacotado responde HTTP 400 vazio, que o
> Testcontainers reporta como "Could not find a valid Docker environment".
> Upgrade para Testcontainers 1.21.3 não resolveu. Enquanto isso, o script
> acima cobre as mesmas garantias contra um Postgres real.

## Princípios que atravessam tudo

1. **O ledger é a fonte da verdade.** Saldo não é uma coluna que se
   atualiza: é a soma das entradas do razão. Nenhum endpoint escreve
   `balance` diretamente.
2. **Dinheiro nunca é ponto flutuante.** `DECIMAL(18,2)` no banco,
   inteiro de centavos no transporte, `Decimal` no Swift.
3. **Toda escrita é idempotente.** O cliente gera a chave; a rede
   móvel cai no meio de um Pix e o retry não pode duplicar a transação.
4. **O servidor decide, o cliente exibe.** Limites, taxas, score e
   validações são autoridade do backend. O app replica regras apenas
   para dar retorno imediato, nunca como controle.
5. **Tudo que toca dinheiro é auditável.** Append-only, com quem, quando,
   de qual dispositivo e sob qual consentimento.

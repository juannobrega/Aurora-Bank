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

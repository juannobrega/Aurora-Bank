-- Núcleo contábil do Aurora Bank.
--
-- Princípio que rege este schema: saldo NÃO é coluna. É a soma dos
-- lançamentos. Nenhuma tabela aqui tem um campo "balance" que a aplicação
-- atualiza — o que existe é um cache derivado (V2), reconstruível.

CREATE TYPE entry_direction AS ENUM ('DEBIT', 'CREDIT');

CREATE TYPE account_type AS ENUM (
    'CHECKING', 'GOAL', 'INVESTMENT',
    'CARD_LIABILITY', 'LOAN_LIABILITY',
    'SETTLEMENT', 'REVENUE', 'EXPENSE', 'FUNDING'
);

CREATE TYPE transaction_state AS ENUM (
    'PENDING', 'AUTHORIZED', 'SETTLED', 'FAILED', 'REVERSED'
);

-- ---------------------------------------------------------------- contas

CREATE TABLE accounts (
    id            uuid PRIMARY KEY,
    tenant_id     uuid         NOT NULL,
    owner_id      uuid,                       -- nulo em contas internas do banco
    type          account_type NOT NULL,
    name          text         NOT NULL,
    currency      char(3)      NOT NULL DEFAULT 'BRL',
    -- Saldo de abertura. Imutável: correções se fazem por lançamento.
    opening_balance numeric(18,2) NOT NULL DEFAULT 0,
    -- Só contas com contrato de crédito podem ficar negativas.
    allows_negative boolean      NOT NULL DEFAULT false,
    closed_at     timestamptz,
    created_at    timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT accounts_currency_brl CHECK (currency = 'BRL')
);

CREATE INDEX accounts_tenant_owner_idx ON accounts (tenant_id, owner_id, type);

-- ----------------------------------------------------------- transações

CREATE TABLE transactions (
    id           uuid PRIMARY KEY,
    tenant_id    uuid              NOT NULL,
    kind         text              NOT NULL,   -- PIX_ENVIADO, APLICACAO, ...
    description  text              NOT NULL,
    state        transaction_state NOT NULL DEFAULT 'SETTLED',
    auth_code    varchar(35)       NOT NULL,
    external_id  text,
    -- Instante no mundo simulado: vem do AuroraClock, não de now().
    occurred_at  timestamptz       NOT NULL,
    settled_at   timestamptz,
    reversed_by  uuid REFERENCES transactions (id),
    failure_code text,
    metadata     jsonb             NOT NULL DEFAULT '{}',
    -- Momento físico da gravação. Este sim usa o relógio real, para
    -- distinguir "quando aconteceu no sandbox" de "quando foi persistido".
    created_at   timestamptz       NOT NULL DEFAULT now(),

    CONSTRAINT transactions_auth_code_unique UNIQUE (auth_code)
);

CREATE INDEX transactions_tenant_occurred_idx
    ON transactions (tenant_id, occurred_at DESC);

-- ----------------------------------------------------------- lançamentos

CREATE TABLE ledger_entries (
    id             uuid PRIMARY KEY,
    transaction_id uuid            NOT NULL REFERENCES transactions (id),
    account_id     uuid            NOT NULL REFERENCES accounts (id),
    direction      entry_direction NOT NULL,
    -- Sempre positivo: o sinal vive em `direction`.
    amount         numeric(18,2)   NOT NULL,
    currency       char(3)         NOT NULL DEFAULT 'BRL',
    -- Ordem canônica global. O snapshot de saldo avança por este número.
    sequence       bigserial       NOT NULL,
    posted_at      timestamptz     NOT NULL,
    effective_date date            NOT NULL,
    created_at     timestamptz     NOT NULL DEFAULT now(),

    CONSTRAINT ledger_amount_positive CHECK (amount > 0)
);

CREATE INDEX ledger_account_seq_idx
    ON ledger_entries (account_id, sequence DESC);
CREATE INDEX ledger_transaction_idx
    ON ledger_entries (transaction_id);
CREATE INDEX ledger_account_date_idx
    ON ledger_entries (account_id, effective_date);

-- ----------------------------------------------- I-1: soma zero por transação
--
-- Verificada no COMMIT, não a cada INSERT: uma transação é inserida em
-- várias linhas, e entre a primeira e a última o saldo está legitimamente
-- desbalanceado. DEFERRABLE INITIALLY DEFERRED é o que torna isso possível
-- sem abrir mão da garantia.

CREATE OR REPLACE FUNCTION assert_transaction_balanced() RETURNS trigger AS $$
DECLARE
    saldo numeric(18,2);
    pernas integer;
    contas integer;
BEGIN
    SELECT
        COALESCE(SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE -amount END), 0),
        COUNT(*),
        COUNT(DISTINCT account_id)
      INTO saldo, pernas, contas
      FROM ledger_entries
     WHERE transaction_id = COALESCE(NEW.transaction_id, OLD.transaction_id);

    -- Transação apagada por completo (estorno técnico) não precisa balancear.
    IF pernas = 0 THEN
        RETURN NULL;
    END IF;

    IF saldo <> 0 THEN
        RAISE EXCEPTION
            'I-1 violada: transação % soma % em vez de zero',
            COALESCE(NEW.transaction_id, OLD.transaction_id), saldo
            USING ERRCODE = 'check_violation';
    END IF;

    IF pernas < 2 OR contas < 2 THEN
        RAISE EXCEPTION
            'I-2 violada: transação % tem % perna(s) em % conta(s)',
            COALESCE(NEW.transaction_id, OLD.transaction_id), pernas, contas
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER ledger_entries_balanced
    AFTER INSERT OR UPDATE ON ledger_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION assert_transaction_balanced();

-- --------------------------------------------- append-only: sem UPDATE/DELETE
--
-- Correção contábil se faz com lançamento de estorno. Um UPDATE apagaria a
-- evidência do próprio erro, que é justamente o que a auditoria precisa ver.

CREATE OR REPLACE FUNCTION reject_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION
        'ledger_entries é append-only: use um lançamento de estorno'
        USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ledger_entries_append_only
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW EXECUTE FUNCTION reject_mutation();

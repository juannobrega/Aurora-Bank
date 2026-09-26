-- Camada bancária: transações com contexto de negócio, cartões, cofrinhos,
-- investimentos, empréstimos, chaves Pix e idempotência.

CREATE TYPE tx_category AS ENUM (
    'moradia','mercado','restaurantes','transporte','assinaturas','saude',
    'educacao','lazer','transferencia','investimento','salario','rendimento',
    'credito','outros'
);

CREATE TYPE tx_method AS ENUM (
    'pix','debito','credito','boleto','ted','cofrinho','aplicacao',
    'emprestimo','recarga'
);

-- Contexto de negócio da transação do razão: o que o extrato exibe.
CREATE TABLE tx_details (
    transaction_id uuid PRIMARY KEY REFERENCES transactions (id) ON DELETE CASCADE,
    user_id        uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title          text        NOT NULL,
    counterparty   text        NOT NULL,
    category       tx_category NOT NULL,
    method         tx_method   NOT NULL,
    -- Sinal do ponto de vista do dono: denormalizado para filtrar
    -- "só entradas" sem varrer os lançamentos.
    is_credit      boolean     NOT NULL,
    amount         numeric(18,2) NOT NULL CHECK (amount > 0),
    note           text,
    metadata       jsonb       NOT NULL DEFAULT '{}'
);

CREATE INDEX tx_details_user_idx ON tx_details (user_id);
CREATE INDEX tx_details_category_idx ON tx_details (user_id, category);

-- ------------------------------------------------------------- chaves Pix

CREATE TYPE pix_key_kind AS ENUM ('cpf','celular','email','aleatoria');

CREATE TABLE pix_keys (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind       pix_key_kind NOT NULL,
    value      text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pix_keys_value_unique UNIQUE (value)
);

CREATE INDEX pix_keys_user_idx ON pix_keys (user_id);

-- Contatos: para quem já se enviou Pix.
CREATE TABLE contacts (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name       text NOT NULL,
    key_value  text NOT NULL,
    bank       text,
    last_used_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT contacts_unique UNIQUE (user_id, key_value)
);

-- ---------------------------------------------------------------- cartões

CREATE TYPE card_kind AS ENUM ('fisico','virtual');

CREATE TABLE cards (
    id            uuid PRIMARY KEY,
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- Conta de passivo do cartão: o saldo dela É a fatura em aberto.
    liability_account_id uuid NOT NULL REFERENCES accounts (id),
    kind          card_kind NOT NULL DEFAULT 'fisico',
    last_four     char(4) NOT NULL,
    expiry        varchar(5) NOT NULL,
    credit_limit  numeric(18,2) NOT NULL DEFAULT 5000,
    blocked       boolean NOT NULL DEFAULT false,
    contactless   boolean NOT NULL DEFAULT true,
    online_purchases boolean NOT NULL DEFAULT true,
    international boolean NOT NULL DEFAULT false,
    invoice_due_day smallint NOT NULL DEFAULT 10,
    created_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT cards_limit_positive CHECK (credit_limit >= 0)
);

CREATE INDEX cards_user_idx ON cards (user_id);

-- -------------------------------------------------------------- cofrinhos

CREATE TABLE goals (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- Conta do cofrinho: `saved` é o saldo dela, não um campo solto.
    account_id uuid NOT NULL REFERENCES accounts (id),
    name       text NOT NULL,
    target     numeric(18,2) NOT NULL CHECK (target > 0),
    symbol     text NOT NULL DEFAULT 'banknote.fill',
    deadline   date,
    created_at timestamptz NOT NULL DEFAULT now(),
    archived_at timestamptz
);

CREATE INDEX goals_user_idx ON goals (user_id) WHERE archived_at IS NULL;

-- ---------------------------------------------------------- investimentos

CREATE TABLE investment_products (
    id            text PRIMARY KEY,
    name          text NOT NULL,
    rate_label    text NOT NULL,
    liquidity     text NOT NULL,
    annual_yield  numeric(6,4) NOT NULL,
    accent        text NOT NULL
);

CREATE TABLE holdings (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    product_id text NOT NULL REFERENCES investment_products (id),
    account_id uuid NOT NULL REFERENCES accounts (id),
    invested   numeric(18,2) NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT holdings_unique UNIQUE (user_id, product_id)
);

-- ------------------------------------------------------------ empréstimos

CREATE TYPE loan_state AS ENUM ('ACTIVE','SETTLED','DEFAULTED');

CREATE TABLE loans (
    id            uuid PRIMARY KEY,
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    liability_account_id uuid NOT NULL REFERENCES accounts (id),
    principal     numeric(18,2) NOT NULL CHECK (principal > 0),
    monthly_rate  numeric(6,4) NOT NULL,
    installments  smallint NOT NULL CHECK (installments > 0),
    state         loan_state NOT NULL DEFAULT 'ACTIVE',
    contracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE installments (
    id        uuid PRIMARY KEY,
    loan_id   uuid NOT NULL REFERENCES loans (id) ON DELETE CASCADE,
    number    smallint NOT NULL,
    amount    numeric(18,2) NOT NULL CHECK (amount > 0),
    due_date  date NOT NULL,
    paid_at   timestamptz,

    CONSTRAINT installments_unique UNIQUE (loan_id, number)
);

CREATE INDEX installments_due_idx ON installments (loan_id, due_date)
    WHERE paid_at IS NULL;

-- Parcela paga é imutável (I-6): quitação não se desfaz por UPDATE.
CREATE OR REPLACE FUNCTION reject_paid_installment_change() RETURNS trigger AS $$
BEGIN
    IF OLD.paid_at IS NOT NULL THEN
        RAISE EXCEPTION 'I-6 violada: parcela já paga não pode ser alterada'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER installments_paid_immutable
    BEFORE UPDATE ON installments
    FOR EACH ROW EXECUTE FUNCTION reject_paid_installment_change();

-- ----------------------------------------------------------- notificações

CREATE TYPE notification_kind AS ENUM ('transaction','security','offer','bill');

CREATE TABLE notifications (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind       notification_kind NOT NULL,
    title      text NOT NULL,
    message    text NOT NULL,
    read_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);

-- ------------------------------------------------------------ idempotência
--
-- A rede móvel cai no meio de um Pix; o app repete a chamada. Sem isto, o
-- dinheiro sai duas vezes.

CREATE TABLE idempotency_keys (
    id           uuid PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    endpoint     text NOT NULL,
    key_value    text NOT NULL,
    request_hash text NOT NULL,
    status       smallint,
    response     jsonb,
    created_at   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT idempotency_unique UNIQUE (user_id, endpoint, key_value)
);

CREATE INDEX idempotency_cleanup_idx ON idempotency_keys (created_at);

-- Catálogo de produtos de investimento.
INSERT INTO investment_products (id, name, rate_label, liquidity, annual_yield, accent) VALUES
 ('cdb',   'CDB Aurora',               '110% do CDI',                'diária',         0.1155, 'cyan'),
 ('selic', 'Tesouro Selic 2029',       'Selic + 0,05%',              'D+1',            0.1055, 'sky'),
 ('lci',   'LCI Aurora 90 dias',       '93% do CDI, isento de IR',   'no vencimento',  0.0977, 'violet'),
 ('fii',   'Fundo Imobiliário AURA11', 'Renda variável',             'D+2',            0.0920, 'amber');

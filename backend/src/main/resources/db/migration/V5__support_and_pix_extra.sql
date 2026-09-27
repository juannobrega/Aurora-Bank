-- Fecha as últimas lacunas de paridade: atendimento, cobrança Pix
-- registrada, devolução (MED), e consentimentos LGPD.

-- ------------------------------------------------------------ atendimento

CREATE TYPE ticket_status AS ENUM ('ABERTO', 'EM_ANDAMENTO', 'RESOLVIDO', 'FECHADO');
CREATE TYPE ticket_channel AS ENUM ('CHAT', 'OUVIDORIA', 'CHAMADO');

CREATE TABLE support_tickets (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    channel    ticket_channel NOT NULL,
    subject    text NOT NULL,
    status     ticket_status NOT NULL DEFAULT 'ABERTO',
    protocol   varchar(20) NOT NULL,           -- número que o cliente guarda
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ticket_protocol_unique UNIQUE (protocol)
);

CREATE INDEX support_tickets_user_idx ON support_tickets (user_id, created_at DESC);

CREATE TABLE support_messages (
    id         uuid PRIMARY KEY,
    ticket_id  uuid NOT NULL REFERENCES support_tickets (id) ON DELETE CASCADE,
    from_user  boolean NOT NULL,               -- true = cliente, false = atendente
    body       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX support_messages_ticket_idx ON support_messages (ticket_id, created_at);

-- ----------------------------------------------------- cobrança Pix (QR)
--
-- A cobrança gerada no app passa a ser registrada: assim quem paga é
-- reconhecido e o recebedor vê a entrada vinculada à cobrança.

CREATE TABLE pix_charges (
    id           uuid PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    pix_key      text NOT NULL,
    amount       numeric(18,2),                 -- nulo = QR sem valor definido
    description  text,
    txid         varchar(35) NOT NULL,
    paid_by      uuid REFERENCES users (id),
    paid_tx_id   uuid REFERENCES transactions (id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    paid_at      timestamptz,

    CONSTRAINT pix_charge_txid_unique UNIQUE (txid)
);

CREATE INDEX pix_charges_user_idx ON pix_charges (user_id, created_at DESC);

-- Vínculo da devolução (MED) à transação original.
ALTER TABLE tx_details ADD COLUMN refunded_tx_id uuid REFERENCES transactions (id);

-- ----------------------------------------------------- consentimentos LGPD

CREATE TABLE consents (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind       text NOT NULL,                  -- open_finance, marketing, ...
    granted    boolean NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX consents_user_idx ON consents (user_id, created_at DESC);

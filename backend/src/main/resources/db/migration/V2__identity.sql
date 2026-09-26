-- Identidade: usuário, dispositivos confiáveis e biometria facial.
--
-- Este ambiente guarda dados reais e persistentes: quem se cadastra existe
-- de verdade, e ao sair e voltar encontra tudo como deixou.

CREATE TYPE user_status AS ENUM (
    'PENDING_KYC',   -- cadastro iniciado, rosto ainda não validado
    'ACTIVE',
    'BLOCKED',
    'CLOSED'
);

CREATE TYPE device_status AS ENUM ('PENDING', 'TRUSTED', 'REVOKED');

CREATE TABLE users (
    id            uuid PRIMARY KEY,
    full_name     text        NOT NULL,
    cpf           varchar(11) NOT NULL,
    email         text        NOT NULL,
    phone         varchar(11),
    birth_date    date,
    status        user_status NOT NULL DEFAULT 'PENDING_KYC',
    -- PIN: só o hash, nunca o valor. Argon2id com sal por usuário.
    pin_hash      text,
    pin_updated_at timestamptz,
    failed_pin_attempts smallint NOT NULL DEFAULT 0,
    locked_until  timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT users_cpf_unique   UNIQUE (cpf),
    CONSTRAINT users_email_unique UNIQUE (email),
    CONSTRAINT users_cpf_digits   CHECK (cpf ~ '^[0-9]{11}$')
);

-- --------------------------------------------------------------- biometria
--
-- Guarda o TEMPLATE (vetor de características), nunca a fotografia. Um
-- template não permite reconstruir o rosto, e é o que a verificação compara.
-- A imagem original é descartada logo após a extração.
--
-- Mesmo sendo ambiente de estudo, o template fica cifrado em repouso: é
-- dado pessoal sensível pela LGPD (Art. 5º, II) e o jeito certo de
-- aprender é fazendo do jeito certo.

CREATE TABLE face_enrollments (
    id             uuid PRIMARY KEY,
    user_id        uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- Template cifrado (AES-GCM). Nunca a imagem.
    template       bytea NOT NULL,
    -- Nonce do AES-GCM, único por registro.
    template_nonce bytea NOT NULL,
    -- Qual algoritmo gerou o template, para permitir migração futura.
    algorithm      text  NOT NULL,
    -- Confiança da detecção no momento do cadastro (0..1).
    quality        numeric(4,3) NOT NULL,
    -- Prova de vida aprovada na captura.
    liveness_passed boolean NOT NULL DEFAULT false,
    enrolled_at    timestamptz NOT NULL DEFAULT now(),
    revoked_at     timestamptz,

    CONSTRAINT face_quality_range CHECK (quality >= 0 AND quality <= 1)
);

-- Um cadastro facial ativo por usuário.
CREATE UNIQUE INDEX face_active_per_user
    ON face_enrollments (user_id) WHERE revoked_at IS NULL;

-- Tentativas de verificação: trilha de auditoria e antifraude.
CREATE TABLE face_verifications (
    id            uuid PRIMARY KEY,
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    enrollment_id uuid REFERENCES face_enrollments (id),
    succeeded     boolean NOT NULL,
    -- Distância entre os templates: quanto menor, mais parecido.
    score         numeric(5,4),
    liveness_passed boolean NOT NULL DEFAULT false,
    device_id     uuid,
    failure_reason text,
    attempted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX face_verifications_user_idx
    ON face_verifications (user_id, attempted_at DESC);

-- ------------------------------------------------------------ dispositivos
--
-- O aparelho é vinculado à conta. Logout não apaga o vínculo: ao voltar,
-- o mesmo device é reconhecido e o acesso é por PIN ou biometria, sem
-- refazer o cadastro.

CREATE TABLE devices (
    id             uuid PRIMARY KEY,
    user_id        uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- identifierForVendor do iOS: estável por fabricante e instalação.
    hardware_id    text NOT NULL,
    name           text NOT NULL,           -- "iPhone de Juan"
    model          text,                    -- "iPhone14,5"
    os_version     text,
    -- Chave pública do par gerado no Secure Enclave. O app assina os
    -- desafios com a privada, que nunca sai do aparelho.
    public_key     text,
    status         device_status NOT NULL DEFAULT 'PENDING',
    push_token     text,
    last_seen_at   timestamptz,
    registered_at  timestamptz NOT NULL DEFAULT now(),
    revoked_at     timestamptz,

    CONSTRAINT devices_hardware_unique UNIQUE (user_id, hardware_id)
);

CREATE INDEX devices_user_idx ON devices (user_id, status);

-- ----------------------------------------------------------------- sessões
--
-- Logout revoga a sessão, não o dispositivo.

CREATE TABLE sessions (
    id            uuid PRIMARY KEY,
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    device_id     uuid NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    refresh_token_hash text NOT NULL,
    issued_at     timestamptz NOT NULL DEFAULT now(),
    expires_at    timestamptz NOT NULL,
    revoked_at    timestamptz,
    revoked_reason text,

    CONSTRAINT sessions_token_unique UNIQUE (refresh_token_hash)
);

CREATE INDEX sessions_user_active_idx
    ON sessions (user_id, device_id) WHERE revoked_at IS NULL;

-- Vincula a conta do razão ao usuário dono.
ALTER TABLE accounts
    ADD CONSTRAINT accounts_owner_fk
    FOREIGN KEY (owner_id) REFERENCES users (id);

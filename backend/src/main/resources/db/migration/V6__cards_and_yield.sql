-- Cartões como recurso de primeira classe (listar, comprar) e rendimento
-- automático do saldo em conta.

-- Um usuário pode ter vários cartões (físico e virtuais). A V3 assumia um
-- só; aqui o físico ganha número próprio e nasce a possibilidade de virtuais.
ALTER TABLE cards ADD COLUMN card_number varchar(19);
ALTER TABLE cards ADD COLUMN cvv varchar(4);
ALTER TABLE cards ADD COLUMN holder_name text;

-- Preenche os cartões já existentes com um número determinístico.
UPDATE cards SET
    card_number = COALESCE(card_number,
        '5412 ' || lpad((abs(hashtext(id::text)) % 10000)::text, 4, '0')
        || ' ' || lpad((abs(hashtext(id::text || 'a')) % 10000)::text, 4, '0')
        || ' ' || last_four),
    cvv = COALESCE(cvv, lpad((abs(hashtext(id::text || 'cvv')) % 1000)::text, 3, '0'))
WHERE card_number IS NULL;

-- ------------------------------------------------ rendimento automático
--
-- O saldo em conta rende 100% do CDI. Um job credita o rendimento pró-rata
-- do tempo decorrido; esta tabela guarda até quando cada conta já foi
-- remunerada, para não pagar duas vezes o mesmo período.

CREATE TABLE yield_accruals (
    account_id     uuid PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
    last_accrued_at timestamptz NOT NULL DEFAULT now(),
    total_yielded  numeric(18,2) NOT NULL DEFAULT 0
);

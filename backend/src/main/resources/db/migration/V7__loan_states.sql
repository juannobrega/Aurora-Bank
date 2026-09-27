-- Novos estados do empréstimo. Ficam numa migration própria porque o
-- Postgres não deixa usar um valor de enum recém-criado na mesma transação
-- em que ele foi adicionado — a V8 já pode usá-los.
ALTER TYPE loan_state ADD VALUE IF NOT EXISTS 'EM_ANALISE' BEFORE 'ACTIVE';
ALTER TYPE loan_state ADD VALUE IF NOT EXISTS 'RECUSADO' AFTER 'SETTLED';

-- Verificação das invariantes do razão contra um Postgres real.
--
-- Uso:
--   docker compose up -d db
--   docker compose exec -T db psql -U aurora -d aurora \
--     -f /dev/stdin < src/main/resources/db/migration/V1__ledger_core.sql
--   docker compose exec -T db psql -U aurora -d aurora < scripts/verify-ledger.sql
--
-- Serve enquanto o Testcontainers não sobe neste ambiente (ver README).
-- Cada bloco abaixo declara o resultado esperado.

INSERT INTO accounts (id, tenant_id, owner_id, type, name) VALUES
 ('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000001',
  'bbbbbbbb-0000-0000-0000-000000000001','CHECKING','Conta corrente'),
 ('22222222-2222-2222-2222-222222222222','aaaaaaaa-0000-0000-0000-000000000001',
  NULL,'SETTLEMENT','Liquidacao Pix');

\echo '== T1: transacao balanceada -> ACEITA =='
BEGIN;
INSERT INTO transactions (id,tenant_id,kind,description,auth_code,occurred_at)
VALUES ('33333333-3333-3333-3333-333333333333','aaaaaaaa-0000-0000-0000-000000000001',
        'SALARIO','Studio Nuvem','E0000000000000000000000000000001','2026-09-26T15:00:00Z');
INSERT INTO ledger_entries (id,transaction_id,account_id,direction,amount,posted_at,effective_date) VALUES
 (gen_random_uuid(),'33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222','DEBIT',6200.00,'2026-09-26T15:00:00Z','2026-09-26'),
 (gen_random_uuid(),'33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','CREDIT',6200.00,'2026-09-26T15:00:00Z','2026-09-26');
COMMIT;

\echo '== T2: saldo derivado -> 6200.00 =='
SELECT a.opening_balance + COALESCE(SUM(CASE WHEN e.direction='CREDIT' THEN e.amount ELSE -e.amount END),0) AS saldo
  FROM accounts a LEFT JOIN ledger_entries e ON e.account_id=a.id
 WHERE a.id='11111111-1111-1111-1111-111111111111' GROUP BY a.opening_balance;

\echo '== T3: I-1 desbalanceada -> ERRO no COMMIT =='
BEGIN;
INSERT INTO transactions (id,tenant_id,kind,description,auth_code,occurred_at)
VALUES ('44444444-4444-4444-4444-444444444444','aaaaaaaa-0000-0000-0000-000000000001',
        'QUEBRADA','nao soma zero','E0000000000000000000000000000002','2026-09-26T15:00:00Z');
INSERT INTO ledger_entries (id,transaction_id,account_id,direction,amount,posted_at,effective_date) VALUES
 (gen_random_uuid(),'44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111','DEBIT',60.00,'2026-09-26T15:00:00Z','2026-09-26'),
 (gen_random_uuid(),'44444444-4444-4444-4444-444444444444','22222222-2222-2222-2222-222222222222','CREDIT',59.99,'2026-09-26T15:00:00Z','2026-09-26');
COMMIT;

\echo '== T4: I-2 perna unica -> ERRO no COMMIT =='
BEGIN;
INSERT INTO transactions (id,tenant_id,kind,description,auth_code,occurred_at)
VALUES ('55555555-5555-5555-5555-555555555555','aaaaaaaa-0000-0000-0000-000000000001',
        'SOLTA','uma perna','E0000000000000000000000000000003','2026-09-26T15:00:00Z');
INSERT INTO ledger_entries (id,transaction_id,account_id,direction,amount,posted_at,effective_date) VALUES
 (gen_random_uuid(),'55555555-5555-5555-5555-555555555555','11111111-1111-1111-1111-111111111111','DEBIT',10.00,'2026-09-26T15:00:00Z','2026-09-26');
COMMIT;

\echo '== T5: append-only UPDATE -> ERRO =='
UPDATE ledger_entries SET amount=1 WHERE account_id='11111111-1111-1111-1111-111111111111';

\echo '== T6: append-only DELETE -> ERRO =='
DELETE FROM ledger_entries WHERE account_id='11111111-1111-1111-1111-111111111111';

\echo '== T7: valor negativo -> ERRO (ledger_amount_positive) =='
INSERT INTO ledger_entries (id,transaction_id,account_id,direction,amount,posted_at,effective_date)
VALUES (gen_random_uuid(),'33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','DEBIT',-10.00,'2026-09-26T15:00:00Z','2026-09-26');

\echo '== T8: soma global de todos os lancamentos -> 0.00 =='
SELECT COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END),0) AS soma_global FROM ledger_entries;

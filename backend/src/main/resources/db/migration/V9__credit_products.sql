-- Catálogo de produtos de crédito. Antes só havia "empréstimo pessoal"
-- implícito; agora cada modalidade tem taxa, prazo e regras próprias.

CREATE TABLE credit_products (
    id           text PRIMARY KEY,
    name         text NOT NULL,
    description  text NOT NULL,
    monthly_rate numeric(6,4) NOT NULL,
    max_months   smallint NOT NULL,
    min_amount   numeric(18,2) NOT NULL,
    max_amount   numeric(18,2) NOT NULL,
    icon         text NOT NULL,
    accent       text NOT NULL
);

-- Qual produto originou cada empréstimo.
ALTER TABLE loans ADD COLUMN product_id text REFERENCES credit_products (id);

INSERT INTO credit_products (id, name, description, monthly_rate, max_months, min_amount, max_amount, icon, accent) VALUES
 ('pessoal',    'Empréstimo pessoal',
    'Dinheiro na conta, sem burocracia. Aprovação sujeita a análise.',
    0.0249, 24,  500,  20000, 'hand.raised.fill',          'violet'),
 ('consignado', 'Crédito consignado',
    'Taxa menor com desconto em folha. Ideal para prazos longos.',
    0.0179, 48, 1000,  50000, 'building.columns.fill',     'cyan'),
 ('financiamento', 'Financiamento',
    'Para veículo ou imóvel, em parcelas longas.',
    0.0199, 60, 5000, 200000, 'car.fill',                  'sky'),
 ('antecipacao', 'Antecipação de recebíveis',
    'Adiante valores a receber. Prazo curto, liberação imediata.',
    0.0349, 6,   300,  15000, 'clock.arrow.circlepath',    'amber');

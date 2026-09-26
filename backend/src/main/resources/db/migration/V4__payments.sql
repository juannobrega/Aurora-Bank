-- Boletos pagos: impede pagar duas vezes a mesma linha digitável.
--
-- Sem isto, tocar duas vezes no botão cobra duas vezes — e boleto, ao
-- contrário de Pix, tem identidade própria que permite detectar a repetição.

CREATE TABLE boleto_payments (
    digitable_line varchar(48) PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES transactions (id),
    paid_at        timestamptz NOT NULL DEFAULT now()
);

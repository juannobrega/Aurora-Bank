-- Trilha da decisão de crédito.
ALTER TABLE loans ADD COLUMN requested_at   timestamptz;
ALTER TABLE loans ADD COLUMN decided_at     timestamptz;
ALTER TABLE loans ADD COLUMN decided_by     text;
ALTER TABLE loans ADD COLUMN decision_note  text;

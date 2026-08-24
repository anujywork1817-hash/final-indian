-- ============================================
-- 009_invoicing.sql
-- Admin Finance & Accounting module — Phase 5
-- (P&L / Tax-GST reporting are pure computation over existing
-- tables and need no schema changes — this migration is for
-- Invoice Management + Credit/Debit Notes only).
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/009_invoicing.sql
-- ============================================

CREATE SEQUENCE IF NOT EXISTS invoice_number_seq START 1;
CREATE SEQUENCE IF NOT EXISTS note_number_seq START 1;

-- --------------------------------------------
-- One invoice per booking, generated automatically the moment a
-- booking is confirmed (online payment via payment-service, or
-- cash confirmation via booking-service — the same two trigger
-- points the confirmation email already uses). Immutable once
-- issued: there is no UPDATE path anywhere in the app for this
-- table — a correction is a credit or debit note against it, per
-- the "never edit, only reverse/adjust" rule used throughout this
-- module.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS invoices (
    id                       SERIAL PRIMARY KEY,
    invoice_number           VARCHAR(30)   UNIQUE NOT NULL,
    booking_ref              VARCHAR(20)   NOT NULL,
    customer_name            VARCHAR(200)  NOT NULL,
    customer_phone           VARCHAR(15)   NOT NULL,
    billing_country          VARCHAR(100)  NOT NULL DEFAULT 'India',
    tent_name                VARCHAR(200)  NOT NULL,
    location                 VARCHAR(200),
    check_in                 DATE          NOT NULL,
    check_out                DATE          NOT NULL,
    base_amount              NUMERIC(12,2) NOT NULL,
    tax                      NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_amount             NUMERIC(12,2) NOT NULL,
    currency                 VARCHAR(3)    NOT NULL DEFAULT 'INR',
    payment_status_at_issue  VARCHAR(20),
    created_at               TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_booking_ref ON invoices (booking_ref);
CREATE INDEX IF NOT EXISTS idx_invoices_created_at ON invoices (created_at DESC);

-- --------------------------------------------
-- Credit Note (reduces amount due) / Debit Note (increases it).
-- Always references an invoice; the invoice row itself never
-- changes — "outstanding balance" is computed as
-- total_amount - SUM(credit) + SUM(debit) at read time.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS credit_debit_notes (
    id            SERIAL PRIMARY KEY,
    note_number   VARCHAR(30)   UNIQUE NOT NULL,
    invoice_id    INT           NOT NULL REFERENCES invoices(id),
    note_type     VARCHAR(10)   NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    reason        TEXT          NOT NULL,
    issued_by     VARCHAR(100)  NOT NULL,
    created_at    TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_credit_debit_notes_invoice_id ON credit_debit_notes (invoice_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_credit_debit_notes_type'
    ) THEN
        ALTER TABLE credit_debit_notes ADD CONSTRAINT ck_credit_debit_notes_type
            CHECK (note_type IN ('credit', 'debit'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_credit_debit_notes_amount_positive'
    ) THEN
        ALTER TABLE credit_debit_notes ADD CONSTRAINT ck_credit_debit_notes_amount_positive
            CHECK (amount > 0);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_credit_debit_notes_reason_required'
    ) THEN
        ALTER TABLE credit_debit_notes ADD CONSTRAINT ck_credit_debit_notes_reason_required
            CHECK (length(trim(reason)) > 0);
    END IF;
END
$$;

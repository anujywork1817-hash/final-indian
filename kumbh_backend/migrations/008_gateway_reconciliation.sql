-- ============================================
-- 008_gateway_reconciliation.sql
-- Admin Finance & Accounting module — Phase 4
-- (Payment Gateway Settlement + Reconciliation).
--
-- No live Razorpay Settlement API / webhook integration exists
-- in this codebase (this server has no public HTTPS endpoint for
-- Razorpay to call back), so bank settlement data is admin-
-- entered — what an accountant reads off the actual bank
-- statement — rather than a fabricated "auto-fetched" number.
-- Reconciliation only applies to gateway (Razorpay) payments;
-- cash/UPI/card/bank_transfer payments recorded manually in
-- Phase 2 are receipts already in hand, not settlements to match
-- against a later bank deposit.
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/008_gateway_reconciliation.sql
-- ============================================

CREATE TABLE IF NOT EXISTS bank_settlements (
    id               SERIAL PRIMARY KEY,
    booking_ref      VARCHAR(20)   NOT NULL,
    gateway          VARCHAR(20)   NOT NULL DEFAULT 'razorpay',
    settlement_id    VARCHAR(100), -- bank UTR / Razorpay settlement ID
    settlement_date  DATE          NOT NULL,
    amount           NUMERIC(10,2) NOT NULL,
    recorded_by      VARCHAR(100)  NOT NULL,
    note             TEXT,
    created_at       TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bank_settlements_booking_ref ON bank_settlements (booking_ref);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_bank_settlements_amount_positive'
    ) THEN
        ALTER TABLE bank_settlements ADD CONSTRAINT ck_bank_settlements_amount_positive
            CHECK (amount > 0);
    END IF;
    -- One settlement record per booking — a second entry corrects
    -- the first via UPDATE-by-replace is intentionally NOT
    -- supported; see the reversal-only pattern elsewhere in this
    -- schema. Only one settlement is expected per booking today
    -- since bookings are settled in full, one gateway payment
    -- each.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_bank_settlements_booking_ref'
    ) THEN
        ALTER TABLE bank_settlements ADD CONSTRAINT uq_bank_settlements_booking_ref
            UNIQUE (booking_ref);
    END IF;
END
$$;

-- --------------------------------------------
-- Per-gateway fee configuration, so the Gateway Summary and
-- Reconciliation modules can compute an expected net settlement
-- (Gross − Fee − Tax on Fee) instead of assuming it. Rates are
-- PLACEHOLDER — Razorpay's real blended rate varies by
-- instrument (UPI/card/netbanking) and plan; an admin must set
-- the actual contracted rate before these numbers are trusted.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS gateway_settings (
    gateway             VARCHAR(20)   PRIMARY KEY,
    fee_percent         NUMERIC(5,3)  NOT NULL DEFAULT 0,
    tax_on_fee_percent  NUMERIC(5,3)  NOT NULL DEFAULT 0,
    updated_by          VARCHAR(100),
    updated_at          TIMESTAMP     NOT NULL DEFAULT NOW()
);

INSERT INTO gateway_settings (gateway, fee_percent, tax_on_fee_percent) VALUES
    ('razorpay', 2.000, 18.000),
    ('cash', 0, 0),
    ('upi', 0, 0),
    ('card', 0, 0),
    ('bank_transfer', 0, 0),
    ('other', 0, 0)
ON CONFLICT (gateway) DO NOTHING;

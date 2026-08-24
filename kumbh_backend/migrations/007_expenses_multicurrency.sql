-- ============================================
-- 007_expenses_multicurrency.sql
-- Admin Finance & Accounting module — Phase 3
-- (Operating Expenses + Foreign Currency / Multi-Currency).
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/007_expenses_multicurrency.sql
-- ============================================

-- --------------------------------------------
-- Operating Expenses.
--
-- Tents are self-owned, so this replaces a vendor-payout ledger:
-- money going OUT of the business that isn't a customer refund.
-- No UPDATE/edit path is exposed anywhere in the app for this
-- table on purpose — corrections are reversal rows (see
-- reversal_of_id), matching the "never edit, only reverse"
-- rule that already governs refunds.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS expenses (
    id              SERIAL PRIMARY KEY,
    expense_date    DATE            NOT NULL,
    category        VARCHAR(30)     NOT NULL,
    amount          NUMERIC(10,2)   NOT NULL,
    tax             NUMERIC(10,2)   NOT NULL DEFAULT 0,
    payment_mode    VARCHAR(20)     NOT NULL DEFAULT 'cash',
    attachment_url  TEXT,
    approved_by     VARCHAR(100)    NOT NULL,
    note            TEXT,
    -- Set only on a reversal row: points back at the expense it
    -- cancels out. A reversal always carries a negative amount.
    reversal_of_id  INT REFERENCES expenses(id),
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_expenses_date       ON expenses (expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category   ON expenses (category);
CREATE INDEX IF NOT EXISTS idx_expenses_reversal   ON expenses (reversal_of_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_expenses_category'
    ) THEN
        ALTER TABLE expenses ADD CONSTRAINT ck_expenses_category
            CHECK (category IN (
                'Tent Maintenance', 'Transportation', 'Staff Salary', 'Cleaning',
                'Electricity', 'Marketing', 'Rent', 'Insurance', 'Equipment',
                'Repair', 'Other'
            ));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_expenses_payment_mode'
    ) THEN
        ALTER TABLE expenses ADD CONSTRAINT ck_expenses_payment_mode
            CHECK (payment_mode IN ('cash', 'upi', 'card', 'bank_transfer', 'cheque', 'other'));
    END IF;

    -- A normal expense is positive; a reversal (has reversal_of_id
    -- set) is negative — that's what makes it net to zero against
    -- the row it corrects, without ever touching the original row.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_expenses_amount_sign'
    ) THEN
        ALTER TABLE expenses ADD CONSTRAINT ck_expenses_amount_sign
            CHECK (
                (reversal_of_id IS NULL AND amount > 0)
                OR (reversal_of_id IS NOT NULL AND amount < 0)
            );
    END IF;
END
$$;

-- --------------------------------------------
-- Foreign Currency / Multi-Currency.
--
-- exchange_rates holds only the CURRENT rate per currency —
-- updating it must never alter a historical booking's locked-in
-- rate. That lock lives on the booking row itself (below), set
-- once at booking time and never recalculated.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS exchange_rates (
    currency_code  VARCHAR(3)    PRIMARY KEY,
    rate_to_inr    NUMERIC(12,6) NOT NULL,
    updated_by     VARCHAR(100),
    updated_at     TIMESTAMP     NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_exchange_rates_positive'
    ) THEN
        ALTER TABLE exchange_rates ADD CONSTRAINT ck_exchange_rates_positive
            CHECK (rate_to_inr > 0);
    END IF;
END
$$;

-- Seed rates — PLACEHOLDER VALUES. An admin must set real,
-- current rates via PUT /admin/exchange-rates/:currency before
-- any foreign-currency booking is taken; these exist only so the
-- table isn't empty and the app doesn't have to special-case a
-- missing row.
INSERT INTO exchange_rates (currency_code, rate_to_inr) VALUES
    ('USD', 90.00),
    ('EUR', 98.00),
    ('GBP', 115.00),
    ('AED', 24.50)
ON CONFLICT (currency_code) DO NOTHING;

-- --------------------------------------------
-- Bookings gain the multi-currency snapshot. currency defaults
-- to INR for every booking made through the app today (which has
-- no currency picker yet) — exchange_rate is 1 and foreign_amount
-- is NULL in that case, so nothing about existing INR bookings
-- changes.
-- --------------------------------------------
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS currency        VARCHAR(3)    NOT NULL DEFAULT 'INR';
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS exchange_rate    NUMERIC(12,6) NOT NULL DEFAULT 1;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS foreign_amount   NUMERIC(12,2);

CREATE INDEX IF NOT EXISTS idx_bookings_currency ON bookings (currency);

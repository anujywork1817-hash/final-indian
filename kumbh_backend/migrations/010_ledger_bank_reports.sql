-- ============================================
-- 010_ledger_bank_reports.sql
-- Admin Finance & Accounting module — Phase 6
-- (Bank/Cash Management + double-entry Ledger).
-- Reports (Phase 6's other deliverable) are pure read-only
-- exports over existing tables and need no schema of their own.
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/010_ledger_bank_reports.sql
-- ============================================

-- --------------------------------------------
-- Bank/Cash accounts. Two rows are seeded by default — "Cash"
-- (the till at the tent) and "Bank/Gateway" (the account
-- Razorpay settles into) — because every ledger posting in this
-- app uses exactly one of those two account names. More can be
-- added, but a new account only shows real activity once
-- something in the code posts ledger entries against it.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS bank_accounts (
    id                    SERIAL PRIMARY KEY,
    account_name          VARCHAR(100)  UNIQUE NOT NULL,
    account_type          VARCHAR(10)   NOT NULL DEFAULT 'bank',
    account_number        VARCHAR(50),
    opening_balance       NUMERIC(12,2) NOT NULL DEFAULT 0,
    opening_balance_date  DATE          NOT NULL DEFAULT CURRENT_DATE,
    created_at            TIMESTAMP     NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_bank_accounts_type'
    ) THEN
        ALTER TABLE bank_accounts ADD CONSTRAINT ck_bank_accounts_type
            CHECK (account_type IN ('bank', 'cash'));
    END IF;
END
$$;

INSERT INTO bank_accounts (account_name, account_type, account_number, opening_balance)
VALUES
    ('Cash', 'cash', NULL, 0),
    ('Bank/Gateway', 'bank', NULL, 0)
ON CONFLICT (account_name) DO NOTHING;

-- --------------------------------------------
-- Ledger entries — double-entry, system-generated only.
--
-- Every real transaction posts exactly two rows sharing the same
-- (reference_type, reference_id): one with debit set and credit
-- 0, one with credit set and debit 0, for the same amount. There
-- is no UPDATE path anywhere in the app for this table — a
-- refund or an expense reversal posts a NEW pair with the
-- accounts swapped (see reversal_of_group), never touches the
-- original rows. This is what makes "total Dr = total Cr always"
-- an invariant of the posting code, not something enforced by a
-- constraint that could itself be bypassed.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS ledger_entries (
    id               SERIAL PRIMARY KEY,
    entry_date       DATE          NOT NULL,
    reference_type   VARCHAR(30)   NOT NULL, -- 'booking_payment' | 'refund' | 'expense' | 'expense_reversal'
    reference_id     VARCHAR(50)   NOT NULL, -- booking_ref / expense id, etc.
    account          VARCHAR(100)  NOT NULL, -- 'Cash' | 'Bank/Gateway' | 'Customer/Revenue' | 'Operating Expense: <category>'
    debit            NUMERIC(12,2) NOT NULL DEFAULT 0,
    credit           NUMERIC(12,2) NOT NULL DEFAULT 0,
    narration        TEXT,
    created_at       TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ledger_entries_reference ON ledger_entries (reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_account   ON ledger_entries (account);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_date       ON ledger_entries (entry_date DESC);

DO $$
BEGIN
    -- Exactly one side of every row is non-zero — a row is never
    -- both a debit and a credit at once, and never neither.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_ledger_entries_one_sided'
    ) THEN
        ALTER TABLE ledger_entries ADD CONSTRAINT ck_ledger_entries_one_sided
            CHECK (
                (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
            );
    END IF;
END
$$;

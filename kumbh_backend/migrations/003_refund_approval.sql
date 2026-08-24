-- ============================================
-- 003_refund_approval.sql
--
-- Puts a human approval gate in front of every refund.
--
-- Before: cancelling a booking recorded a refund as 'pending'
-- and immediately fired the Razorpay call. Money left the
-- account with no one reviewing it.
--
-- After: a cancellation records the refund as
-- 'awaiting_approval' and stops. Staff approve (-> 'pending',
-- which the existing worker then executes) or reject
-- (-> 'rejected', terminal, nothing is sent).
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/003_refund_approval.sql
-- ============================================

-- --------------------------------------------
-- Audit of who decided what, and why.
-- --------------------------------------------
ALTER TABLE refunds ADD COLUMN IF NOT EXISTS requested_at      TIMESTAMP;
ALTER TABLE refunds ADD COLUMN IF NOT EXISTS reviewed_by       VARCHAR(100);
ALTER TABLE refunds ADD COLUMN IF NOT EXISTS reviewed_at       TIMESTAMP;
ALTER TABLE refunds ADD COLUMN IF NOT EXISTS rejection_reason  TEXT;

-- Existing rows predate the gate; treat their creation as the
-- request time so the admin queue can sort consistently.
UPDATE refunds SET requested_at = created_at WHERE requested_at IS NULL;

-- --------------------------------------------
-- Widen the status enum.
--
-- The CHECK constraint has to be dropped and recreated —
-- there is no ALTER ... ADD VALUE for a CHECK the way there is
-- for a native enum type.
-- --------------------------------------------
ALTER TABLE refunds DROP CONSTRAINT IF EXISTS ck_refunds_status;

ALTER TABLE refunds ADD CONSTRAINT ck_refunds_status
    CHECK (status IN (
        'awaiting_approval',  -- NEW: waiting on a human decision
        'rejected',           -- NEW: staff declined; terminal, nothing sent
        'pending',            -- approved, queued for the gateway
        'processing',
        'succeeded',
        'failed',
        'manual',
        'not_applicable'
    ));

-- --------------------------------------------
-- A rejected refund must record why.
--
-- Without this, "rejected" is an unexplained refusal to return
-- someone's money, which is exactly the kind of thing that has
-- to be answerable months later.
-- --------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refunds_rejected_has_reason'
    ) THEN
        ALTER TABLE refunds ADD CONSTRAINT ck_refunds_rejected_has_reason
            CHECK (
                status <> 'rejected'
                OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0)
            );
    END IF;

    -- Anything past the gate must say who let it through.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refunds_reviewed_has_reviewer'
    ) THEN
        ALTER TABLE refunds ADD CONSTRAINT ck_refunds_reviewed_has_reviewer
            CHECK (
                reviewed_at IS NULL
                OR (reviewed_by IS NOT NULL AND length(trim(reviewed_by)) > 0)
            );
    END IF;
END
$$;

-- Admin queue reads "everything awaiting a decision, oldest
-- first" on every page load.
CREATE INDEX IF NOT EXISTS idx_refunds_awaiting_approval
    ON refunds (requested_at)
    WHERE status = 'awaiting_approval';

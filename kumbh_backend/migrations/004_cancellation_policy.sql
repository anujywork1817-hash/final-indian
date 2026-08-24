-- ============================================
-- 004_cancellation_policy.sql
-- Tiered cancellation & refund policy, per tent.
--
-- Idempotent: safe to run repeatedly against the same database.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/004_cancellation_policy.sql
-- ============================================

-- --------------------------------------------
-- Per-tent policy configuration.
--
-- policy_type NON_REFUNDABLE overrides everything else and
-- always yields a ₹0 refund. Any other value runs the standard
-- time-based ladder (FREE_CANCELLATION -> PARTIAL_REFUND ->
-- ONE_NIGHT_PENALTY) using this tent's configured windows — the
-- three non-NON_REFUNDABLE values are treated identically as
-- config today; TierApplied (the per-cancellation OUTCOME, not
-- this column) is what actually names the rung the cancellation
-- landed on. See the assumptions sent with this change if this
-- reading isn't what was intended.
--
-- Hours are used rather than absolute deadlines so the same
-- config applies uniformly across every booking for a tent; the
-- concrete deadline for a given booking (check-in minus these
-- hours) is computed at query time, not stored, so it can never
-- drift from the source config.
-- --------------------------------------------
ALTER TABLE tents ADD COLUMN IF NOT EXISTS cancellation_policy_type VARCHAR(30) NOT NULL DEFAULT 'FREE_CANCELLATION';
ALTER TABLE tents ADD COLUMN IF NOT EXISTS free_cancellation_hours INT NOT NULL DEFAULT 168;
ALTER TABLE tents ADD COLUMN IF NOT EXISTS partial_refund_penalty_percent NUMERIC(5,2) NOT NULL DEFAULT 30;
ALTER TABLE tents ADD COLUMN IF NOT EXISTS late_cancellation_hours INT NOT NULL DEFAULT 24;
ALTER TABLE tents ADD COLUMN IF NOT EXISTS no_show_cutoff_hours INT NOT NULL DEFAULT 6;
ALTER TABLE tents ADD COLUMN IF NOT EXISTS no_show_penalty_percent NUMERIC(5,2) NOT NULL DEFAULT 100;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_tents_cancellation_policy_type'
    ) THEN
        ALTER TABLE tents ADD CONSTRAINT ck_tents_cancellation_policy_type
            CHECK (cancellation_policy_type IN (
                'FREE_CANCELLATION', 'PARTIAL_REFUND', 'ONE_NIGHT_PENALTY', 'NON_REFUNDABLE'
            ));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_tents_cancellation_hours_order'
    ) THEN
        -- The late-cancellation cutoff must never be later than
        -- the free-cancellation deadline, or the ladder would be
        -- unreachable in the middle (PARTIAL_REFUND) tier.
        ALTER TABLE tents ADD CONSTRAINT ck_tents_cancellation_hours_order
            CHECK (late_cancellation_hours <= free_cancellation_hours);
    END IF;
END
$$;

-- --------------------------------------------
-- Booking-side state needed to decide/act on cancellation and
-- no-show. `status` already carries pending/confirmed/completed/
-- cancelled (schema.sql); this adds 'no_show' to the same
-- column rather than introducing a parallel field, and adds the
-- timestamps needed to compute and audit tier decisions.
-- --------------------------------------------
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_at   TIMESTAMP;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS checked_in_at  TIMESTAMP;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_bookings_status'
    ) THEN
        ALTER TABLE bookings ADD CONSTRAINT ck_bookings_status
            CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no_show'));
    END IF;
END
$$;

-- --------------------------------------------
-- Cancellation/refund audit log.
--
-- Distinct from the `refunds` table (which holds the current,
-- mutable state of one refund per booking): this is an
-- append-only event trail so support can reconstruct exactly
-- what happened and when, even across retries, approvals, and
-- the no-show cron — each of which updates the same `refunds`
-- row multiple times over its life.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS refund_audit_log (
    id                   SERIAL PRIMARY KEY,
    booking_ref          VARCHAR(20)  NOT NULL,
    event                VARCHAR(30)  NOT NULL,
    tier_applied         VARCHAR(30),
    refund_amount_paise  BIGINT,
    penalty_amount_paise BIGINT,
    -- 'user:<phone>', 'admin:<username>', or 'system:<job-name>'
    triggered_by         VARCHAR(80)  NOT NULL,
    note                 TEXT,
    created_at           TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refund_audit_log_booking_ref ON refund_audit_log (booking_ref);
CREATE INDEX IF NOT EXISTS idx_refund_audit_log_created_at  ON refund_audit_log (created_at DESC);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refund_audit_log_event'
    ) THEN
        ALTER TABLE refund_audit_log ADD CONSTRAINT ck_refund_audit_log_event
            CHECK (event IN (
                'CANCELLED', 'NO_SHOW', 'CHECKED_IN',
                'REFUND_APPROVED', 'REFUND_REJECTED',
                'REFUND_SETTLED', 'REFUND_RETRY_QUEUED'
            ));
    END IF;
END
$$;

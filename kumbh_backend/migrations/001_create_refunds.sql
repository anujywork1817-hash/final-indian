-- ============================================
-- 001_create_refunds.sql
-- Refunds on booking cancellation.
--
-- Idempotent: safe to run repeatedly against the same database.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/001_create_refunds.sql
-- ============================================

-- --------------------------------------------
-- Drift repair: columns the Go services already
-- read/write but that schema.sql never declared.
-- A database created purely from schema.sql is
-- missing these, so payment-service silently logs
-- "could not store razorpay_order_id" and the FCM
-- lookups fail. Added here so a fresh DB matches
-- what the code actually expects.
-- --------------------------------------------
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS razorpay_order_id VARCHAR(100);
ALTER TABLE users    ADD COLUMN IF NOT EXISTS fcm_token         TEXT;

-- --------------------------------------------
-- Refunds
--
-- Money is stored in PAISE as BIGINT, never as a
-- float/DECIMAL, so that percentage splits and
-- gateway amounts round exactly once, here, and
-- never drift.
--
-- Deliberately NOT foreign-keyed to bookings:
-- bookings are hard-deleted by the user, by two
-- admin endpoints and by a nightly cron. A refund
-- is a financial record and must outlive the row
-- that produced it.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS refunds (
    id                   SERIAL PRIMARY KEY,

    -- snapshot of the booking, so this row stands alone
    booking_ref          VARCHAR(20)  NOT NULL,
    phone                VARCHAR(15)  NOT NULL,
    tent_name            VARCHAR(200),
    check_in             DATE,

    -- gateway linkage
    razorpay_payment_id  VARCHAR(100),
    razorpay_refund_id   VARCHAR(100),

    -- amounts, all in paise
    booking_amount_paise BIGINT       NOT NULL,
    refund_amount_paise  BIGINT       NOT NULL,
    fee_paise            BIGINT       NOT NULL DEFAULT 0,

    -- audit of WHY this number was chosen
    policy_rule          VARCHAR(80),
    policy_percent       NUMERIC(6,3),
    currency             VARCHAR(3)   NOT NULL DEFAULT 'INR',

    -- pending      : owed, not yet sent to gateway
    -- processing   : claimed by a worker, gateway call in flight
    -- succeeded    : gateway confirmed
    -- failed       : gateway rejected; retryable
    -- manual       : cash booking, staff must refund by hand
    -- not_applicable: nothing owed (unpaid booking, or 0% tier)
    status               VARCHAR(20)  NOT NULL DEFAULT 'pending',

    attempts             INT          NOT NULL DEFAULT 0,
    last_error           TEXT,
    idempotency_key      VARCHAR(80)  NOT NULL,

    created_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
    settled_at           TIMESTAMP
);

-- --------------------------------------------
-- Constraints that make double-refund impossible
-- at the database level, not merely unlikely.
--
-- uq_refunds_booking_ref is the important one: a
-- second INSERT for an already-refunded booking
-- cannot succeed no matter how many concurrent
-- cancel requests race, or how many times a retry
-- fires. It is not an `if` check in application
-- code — it is enforced by the DB.
-- --------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_refunds_booking_ref
    ON refunds (booking_ref);

-- One gateway refund id can never be recorded twice.
CREATE UNIQUE INDEX IF NOT EXISTS uq_refunds_razorpay_refund_id
    ON refunds (razorpay_refund_id)
    WHERE razorpay_refund_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_refunds_idempotency_key
    ON refunds (idempotency_key);

-- Lookup index for the retry worker and admin console.
CREATE INDEX IF NOT EXISTS idx_refunds_status     ON refunds (status);
CREATE INDEX IF NOT EXISTS idx_refunds_phone      ON refunds (phone);
CREATE INDEX IF NOT EXISTS idx_refunds_created_at ON refunds (created_at DESC);

-- --------------------------------------------
-- Value constraints. Added defensively so that
-- re-running this file on a DB that already has
-- the table is still a no-op.
-- --------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refunds_status'
    ) THEN
        ALTER TABLE refunds ADD CONSTRAINT ck_refunds_status
            CHECK (status IN (
                'pending', 'processing', 'succeeded',
                'failed', 'manual', 'not_applicable'
            ));
    END IF;

    -- A refund can never exceed what was actually collected,
    -- and can never be negative. Enforced by the DB so a bad
    -- policy config cannot over-refund.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refunds_amount_bounds'
    ) THEN
        ALTER TABLE refunds ADD CONSTRAINT ck_refunds_amount_bounds
            CHECK (
                refund_amount_paise >= 0
                AND fee_paise       >= 0
                AND booking_amount_paise >= 0
                AND refund_amount_paise + fee_paise <= booking_amount_paise
            );
    END IF;

    -- A succeeded refund must carry the gateway's id.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refunds_succeeded_has_gateway_id'
    ) THEN
        ALTER TABLE refunds ADD CONSTRAINT ck_refunds_succeeded_has_gateway_id
            CHECK (
                status <> 'succeeded'
                OR razorpay_refund_id IS NOT NULL
            );
    END IF;
END
$$;

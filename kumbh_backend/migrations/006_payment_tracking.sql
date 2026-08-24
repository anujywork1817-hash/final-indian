-- ============================================
-- 006_payment_tracking.sql
-- Admin Finance & Accounting module — Phase 2
-- (Customer Payment Tracking + Revenue Summary support).
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/006_payment_tracking.sql
-- ============================================

-- --------------------------------------------
-- payments gains the fields needed to record a
-- manual/partial payment (cash, UPI, bank transfer taken at the
-- tent), not just a Razorpay gateway capture. razorpay_order/
-- razorpay_payment/razorpay_signature stay NULL for these rows —
-- payment_mode and transaction_id are the generalized fields.
-- --------------------------------------------
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_mode   VARCHAR(20) NOT NULL DEFAULT 'razorpay';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS transaction_id VARCHAR(150);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS recorded_by    VARCHAR(100);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS note           TEXT;

CREATE INDEX IF NOT EXISTS idx_payments_booking_ref ON payments (booking_ref);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_payments_mode'
    ) THEN
        ALTER TABLE payments ADD CONSTRAINT ck_payments_mode
            CHECK (payment_mode IN ('razorpay', 'cash', 'upi', 'card', 'bank_transfer', 'other'));
    END IF;

    -- A payment recorded by hand must be attributable, for the
    -- same reason a rejected refund must carry a reason.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_payments_manual_has_recorder'
    ) THEN
        ALTER TABLE payments ADD CONSTRAINT ck_payments_manual_has_recorder
            CHECK (
                payment_mode = 'razorpay'
                OR (recorded_by IS NOT NULL AND length(trim(recorded_by)) > 0)
            );
    END IF;
END
$$;

-- --------------------------------------------
-- Widen refund_audit_log (created in 004) to also cover a
-- recorded customer payment — the audit trail should show money
-- coming IN, not just refunds going out.
-- --------------------------------------------
ALTER TABLE refund_audit_log DROP CONSTRAINT IF EXISTS ck_refund_audit_log_event;
ALTER TABLE refund_audit_log ADD CONSTRAINT ck_refund_audit_log_event
    CHECK (event IN (
        'CANCELLED', 'NO_SHOW', 'CHECKED_IN',
        'REFUND_APPROVED', 'REFUND_REJECTED',
        'REFUND_SETTLED', 'REFUND_RETRY_QUEUED',
        'PAYMENT_RECORDED'
    ));

-- Approving a refund now requires a written justification, the same
-- way rejecting one already did (ck_refunds_rejected_has_reason).
-- Money leaving the account has to be explainable in an audit years
-- later, so the reason is stored on the refund row itself rather
-- than only in the append-only audit log.
ALTER TABLE refunds ADD COLUMN IF NOT EXISTS approval_reason TEXT;

-- Enforced in the DB as well as the handler, so a refund cannot be
-- approved without a reason by any path (script, psql, future code).
-- Only applies going forward: rows already approved before this
-- migration are grandfathered via the approval_reason IS NULL escape,
-- otherwise the constraint would fail to validate on existing data.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_refunds_approved_has_reason'
    ) THEN
        ALTER TABLE refunds ADD CONSTRAINT ck_refunds_approved_has_reason
            CHECK (
                approval_reason IS NULL
                OR length(btrim(approval_reason)) > 0
            );
    END IF;
END $$;

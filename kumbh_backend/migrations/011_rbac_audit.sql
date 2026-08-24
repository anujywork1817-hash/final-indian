-- ============================================
-- 011_rbac_audit.sql
-- Admin Finance & Accounting module — Phase 7 QA pass
-- (role-based access + a general admin audit log).
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/011_rbac_audit.sql
-- ============================================

ALTER TABLE admins ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'staff';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_admins_role'
    ) THEN
        ALTER TABLE admins ADD CONSTRAINT ck_admins_role
            CHECK (role IN ('super_admin', 'staff'));
    END IF;
END
$$;

-- Every admin account that existed before RBAC was added keeps
-- full access — RBAC only constrains accounts created after this
-- point, via the new create-admin endpoint, which defaults new
-- accounts to 'staff' unless a super_admin explicitly grants more.
UPDATE admins SET role = 'super_admin' WHERE role = 'staff';

-- --------------------------------------------
-- General admin audit log — distinct from refund_audit_log
-- (which is specifically the refund/payment/cancellation trail).
-- This covers the other sensitive admin mutations: tent/coupon
-- edits, booking status changes, user block/unblock, KYC
-- verification, and admin account changes. Every service shares
-- this one physical database, so any service writes here
-- directly with its own `db` connection — same pattern already
-- used for cross-service tables like ledger_entries.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS admin_audit_log (
    id              SERIAL PRIMARY KEY,
    admin_username  VARCHAR(100) NOT NULL,
    action          VARCHAR(50)  NOT NULL,
    target_type     VARCHAR(50),
    target_id       VARCHAR(100),
    details         TEXT,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_created_at ON admin_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin       ON admin_audit_log (admin_username);

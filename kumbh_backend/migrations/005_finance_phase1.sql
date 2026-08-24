-- ============================================
-- 005_finance_phase1.sql
-- Admin Finance & Accounting module — Phase 1 (data model).
--
-- Adds what Phase 1 of the finance module needs on top of the
-- existing schema. Deliberately does NOT create a separate
-- `customers` table: `users` (keyed by phone) already is the
-- customer entity in this app — one phone, one customer — so a
-- second table would just be a copy that could drift out of
-- sync. `country` is added to `users` instead.
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/005_finance_phase1.sql
-- ============================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS country VARCHAR(100) NOT NULL DEFAULT 'India';

CREATE INDEX IF NOT EXISTS idx_users_country ON users (country);

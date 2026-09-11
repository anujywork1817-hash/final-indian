-- ============================================
-- 017_rate_limits.sql
-- BUG-21: sendOTP, verifyOTP and adminLogin had no throttling at
-- all. A 6-digit OTP is 1,000,000 possibilities — trivially brute-
-- forceable against verifyOTP with no attempt cap, and sendOTP could
-- be hit in a loop to SMS-bomb any phone number. adminLogin had the
-- same gap against admin passwords.
--
-- A DB-backed counter (not in-memory) so the limit holds across
-- every instance behind the load balancer, not just whichever one
-- happens to receive a given request.
-- ============================================

CREATE TABLE IF NOT EXISTS rate_limits (
    key          VARCHAR(200) PRIMARY KEY,
    count        INT NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Rows are tiny and short-lived (a window is a few minutes); this
-- just keeps the table from growing unbounded if a cleanup job is
-- never added — a lookup by key is O(1) via the primary key either
-- way.
CREATE INDEX IF NOT EXISTS idx_rate_limits_window_start ON rate_limits (window_start);

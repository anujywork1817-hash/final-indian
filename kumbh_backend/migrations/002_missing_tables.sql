-- ============================================
-- 002_missing_tables.sql
--
-- Declares tables and columns that the Go services already
-- read and write, but which appear in NO schema file. They
-- exist only in whatever production database was patched by
-- hand, so a database built from schema.sql alone crashes on:
--
--   * any admin login          (missing `admins`)
--   * submitting/reading a review (missing `reviews`)
--   * the whole KYC feature    (missing users.kyc_status etc.)
--
-- Column types and defaults are derived from actual usage in
-- auth-service/handler.go and tent-service/tent_reviews.go.
--
-- Idempotent: safe to run repeatedly.
-- Apply with:
--   psql "$DATABASE_URL" -f migrations/002_missing_tables.sql
-- ============================================

-- --------------------------------------------
-- Admin accounts
--
-- auth-service reads `password_hash` and compares it with
-- bcrypt.CompareHashAndPassword, and allows renaming via
-- `UPDATE admins SET username = ...`, so username must be
-- unique but is not the primary key.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS admins (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(100) UNIQUE NOT NULL,
    password_hash TEXT         NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- --------------------------------------------
-- Tent reviews
--
-- submitReview relies on a UNIQUE violation containing
-- "unique"/"duplicate" to detect a repeat review, so the
-- constraint on booking_ref is load-bearing application
-- logic, not just hygiene.
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS reviews (
    id          SERIAL PRIMARY KEY,
    booking_ref VARCHAR(20) UNIQUE NOT NULL,
    tent_id     INT         NOT NULL REFERENCES tents(id) ON DELETE CASCADE,
    phone       VARCHAR(15) NOT NULL,
    rating      INT         NOT NULL,
    review      TEXT,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_tent_id    ON reviews (tent_id);
CREATE INDEX IF NOT EXISTS idx_reviews_phone      ON reviews (phone);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON reviews (created_at DESC);

DO $$
BEGIN
    -- submitReview already rejects out-of-range values, but the
    -- rating also feeds tents.rating via AVG(), so bad data here
    -- silently corrupts every listing's score.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_reviews_rating_range'
    ) THEN
        ALTER TABLE reviews ADD CONSTRAINT ck_reviews_rating_range
            CHECK (rating BETWEEN 1 AND 5);
    END IF;
END
$$;

-- --------------------------------------------
-- KYC columns on users
--
-- submitKYC writes id_type/id_number and sets kyc_status to
-- 'pending'; adminVerifyKYC moves it to 'verified'/'rejected';
-- adminGetKYC filters on those three values and defaults
-- everything else to 'not_submitted'.
-- --------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS id_type     VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS id_number   VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_status  VARCHAR(20) DEFAULT 'not_submitted';
ALTER TABLE users ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_users_kyc_status ON users (kyc_status);

-- Note: user blocking is implemented by writing the string
-- 'blocked' into users.role (adminBlockUser), not via a
-- dedicated column, so nothing is added for it here.

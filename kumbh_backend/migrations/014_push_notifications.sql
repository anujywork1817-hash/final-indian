-- Push notification platform: per-user preferences, a send log that
-- makes every notification idempotent, plus the three features that
-- had no server-side existence yet (favourites, snan calendar +
-- reminders, news) and therefore nothing to notify *about*.

-- ── Delivery log ─────────────────────────────────────────
-- Every push is recorded before it is considered sent. The unique
-- index on (phone, type, ref_key) is what makes notifications
-- idempotent: the schedulers run daily and would otherwise re-send
-- the same "check-in tomorrow" or "snan is coming" push on every
-- pass. ref_key is the thing being notified about (booking_ref,
-- snan date, article id…) so the same user can be told about two
-- different bookings but never twice about one.
CREATE TABLE IF NOT EXISTS notification_log (
    id          SERIAL PRIMARY KEY,
    phone       VARCHAR(20)  NOT NULL,
    type        VARCHAR(40)  NOT NULL,
    ref_key     VARCHAR(120) NOT NULL DEFAULT '',
    title       TEXT,
    body        TEXT,
    delivered   BOOLEAN      NOT NULL DEFAULT TRUE,
    error       TEXT,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_once
    ON notification_log (phone, type, ref_key);
CREATE INDEX IF NOT EXISTS idx_notification_log_phone ON notification_log (phone, created_at DESC);

-- ── Per-user preferences ─────────────────────────────────
-- Absence of a row means "enabled" — opt-out rather than opt-in, so
-- existing users keep receiving the booking pushes they already get
-- without a backfill.
CREATE TABLE IF NOT EXISTS notification_prefs (
    phone      VARCHAR(20) NOT NULL,
    type       VARCHAR(40) NOT NULL,
    enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMP   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (phone, type)
);

-- ── Favourites ───────────────────────────────────────────
-- Previously in-memory only (Flutter WishlistStore, explicitly "not
-- persisted"), so favourites did not survive an app restart and the
-- server could not act on them at all.
CREATE TABLE IF NOT EXISTS favourites (
    id         SERIAL PRIMARY KEY,
    phone      VARCHAR(20) NOT NULL,
    tent_id    INTEGER     NOT NULL REFERENCES tents(id) ON DELETE CASCADE,
    created_at TIMESTAMP   NOT NULL DEFAULT NOW(),
    UNIQUE (phone, tent_id)
);
CREATE INDEX IF NOT EXISTS idx_favourites_tent ON favourites (tent_id);

-- Lets the favourites watcher detect a genuine price *drop* rather
-- than re-announcing the same price every run.
ALTER TABLE tents ADD COLUMN IF NOT EXISTS last_notified_price INTEGER;

-- ── Snan calendar ────────────────────────────────────────
-- The dates lived only in Flutter constants, so the backend had no
-- idea when a Snan was and could not schedule anything.
CREATE TABLE IF NOT EXISTS snan_events (
    id           SERIAL PRIMARY KEY,
    event_date   DATE         NOT NULL UNIQUE,
    name         VARCHAR(200) NOT NULL,
    significance TEXT,
    location     VARCHAR(200),
    is_amrit     BOOLEAN      NOT NULL DEFAULT FALSE,
    surge        VARCHAR(20)
);

-- One row per user per date they asked to be reminded about.
CREATE TABLE IF NOT EXISTS snan_reminders (
    id         SERIAL PRIMARY KEY,
    phone      VARCHAR(20) NOT NULL,
    event_date DATE        NOT NULL REFERENCES snan_events(event_date) ON DELETE CASCADE,
    created_at TIMESTAMP   NOT NULL DEFAULT NOW(),
    UNIQUE (phone, event_date)
);

INSERT INTO snan_events (event_date, name, significance, location, is_amrit, surge) VALUES
 ('2027-07-17','Karka Sankranti','Opening of the main bathing period','Nashik',FALSE,NULL),
 ('2027-07-18','Guru Purnima','Important religious bathing day','Nashik / Trimbakeshwar',FALSE,NULL),
 ('2027-07-29','Nagar Pradakshina','Major Kumbh procession through the city','Nashik',FALSE,NULL),
 ('2027-08-02','1st Amrit Snan — Ashadh Amavasya','First royal bathing ceremony. The Akhadas conduct their processions; both Ramkund and Kushavarta Kund are central.','Nashik + Trimbakeshwar',TRUE,'2x'),
 ('2027-08-06','Nag Panchami','Auspicious Snan','Trimbakeshwar / Nashik',FALSE,NULL),
 ('2027-08-12','Shravan Putrada Ekadashi','Auspicious Snan','Nashik / Trimbak',FALSE,NULL),
 ('2027-08-17','Shravan Purnima / Raksha Bandhan','Important Purnima Snan','Nashik / Trimbak',FALSE,NULL),
 ('2027-08-31','2nd Amrit Snan — Shravan Amavasya','The main peak royal bathing day. Expect the largest crowds of the entire 2027 season.','Nashik + Trimbakeshwar',TRUE,'2.5x'),
 ('2027-09-05','Rishi Panchami','Important Parva Snan','Nashik + Trimbak',FALSE,NULL),
 ('2027-09-11','3rd Amrit Snan — Vaishnava','Bhadrapada Shuddha Ekadashi, associated with the Vaishnava Akhadas. Main focus is Ramkund.','Nashik / Ramkund',TRUE,'3x'),
 ('2027-09-12','3rd Amrit Snan — Shaiva','Bhadrapada Shuddha Dwadashi, associated with the Shaiva Akhadas. Main focus is Kushavarta Kund.','Trimbakeshwar / Kushavarta',TRUE,'3x'),
 ('2027-09-15','Bhadrapada Purnima','Closing Purnima Snan','Nashik + Trimbak',FALSE,NULL)
ON CONFLICT (event_date) DO NOTHING;

-- ── News ─────────────────────────────────────────────────
-- News was fetched client-side from newsdata.io/gnews, so the server
-- had no record of what had been seen and could not tell "new" from
-- "already shown". external_id is the provider's URL/guid.
CREATE TABLE IF NOT EXISTS news_articles (
    id           SERIAL PRIMARY KEY,
    external_id  VARCHAR(500) NOT NULL UNIQUE,
    title        TEXT         NOT NULL,
    description  TEXT,
    url          TEXT,
    image_url    TEXT,
    source       VARCHAR(120),
    published_at TIMESTAMP,
    pushed_at    TIMESTAMP,
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_news_published ON news_articles (published_at DESC);
-- Partial index: the poller only ever scans for not-yet-pushed rows.
CREATE INDEX IF NOT EXISTS idx_news_unpushed ON news_articles (created_at) WHERE pushed_at IS NULL;

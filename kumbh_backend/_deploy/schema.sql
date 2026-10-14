-- ============================================
-- Kumbh Tent Booking — Database Schema
-- ============================================

-- Users
CREATE TABLE IF NOT EXISTS users (
    id          SERIAL PRIMARY KEY,
    phone       VARCHAR(15) UNIQUE NOT NULL,
    name        VARCHAR(100),
    email       VARCHAR(100),
    role        VARCHAR(20) DEFAULT 'tourist',
    created_at  TIMESTAMP DEFAULT NOW()
);

-- OTP store (replaces in-memory map)
CREATE TABLE IF NOT EXISTS otp_store (
    phone       VARCHAR(15) PRIMARY KEY,
    otp         VARCHAR(6) NOT NULL,
    expires_at  TIMESTAMP NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- Tents
CREATE TABLE IF NOT EXISTS tents (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    class       VARCHAR(20) NOT NULL, -- basic, standard, premium, luxury, vip
    location    VARCHAR(200),
    distance    DECIMAL(5,2),         -- km from Sangam
    rating      DECIMAL(3,2),
    reviews     INT DEFAULT 0,
    price       INT NOT NULL,         -- current price per night
    base_price  INT NOT NULL,         -- original price before surge
    is_surge    BOOLEAN DEFAULT FALSE,
    surge       VARCHAR(10),          -- e.g. "2.5x"
    amenities   TEXT[],               -- array of strings
    images      TEXT[],               -- array of image URLs
    capacity    INT DEFAULT 2,
    total_units INT DEFAULT 5,         -- number of physical tents of this listing
    is_active   BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- Coupons
CREATE TABLE IF NOT EXISTS coupons (
    id            SERIAL PRIMARY KEY,
    code          VARCHAR(50) UNIQUE NOT NULL,
    discount      DECIMAL(5,2) NOT NULL, -- e.g. 0.10 = 10%
    description   VARCHAR(200),
    min_amount    INT DEFAULT 0,         -- minimum booking amount
    max_uses      INT DEFAULT 100,
    used_count    INT DEFAULT 0,
    is_active     BOOLEAN DEFAULT TRUE,
    expires_at    TIMESTAMP,
    created_at    TIMESTAMP DEFAULT NOW()
);

-- Bookings
CREATE TABLE IF NOT EXISTS bookings (
    id            SERIAL PRIMARY KEY,
    booking_ref   VARCHAR(20) UNIQUE NOT NULL,
    phone         VARCHAR(15) NOT NULL,
    tent_id       INT REFERENCES tents(id),
    tent_name     VARCHAR(200),
    location      VARCHAR(200),
    class         VARCHAR(20),
    check_in      DATE NOT NULL,
    check_out     DATE NOT NULL,
    nights        INT NOT NULL,
    guests        INT DEFAULT 1,
    units         INT DEFAULT 1,
    base_amount   DECIMAL(10,2),
    coupon_code   VARCHAR(50),
    discount      DECIMAL(10,2) DEFAULT 0,
    tax           DECIMAL(10,2) DEFAULT 0,
    total_amount  DECIMAL(10,2) NOT NULL,
    status        VARCHAR(20) DEFAULT 'pending', -- pending, confirmed, completed, cancelled
    payment_id    VARCHAR(100),
    guest_name    VARCHAR(200),
    guest_phone   VARCHAR(15),
    id_proof      VARCHAR(100),
    bed_type      VARCHAR(20) DEFAULT 'Single',
    gender_preference VARCHAR(20) DEFAULT 'Mixed',
    addons        TEXT,
    created_at    TIMESTAMP DEFAULT NOW(),
    updated_at    TIMESTAMP DEFAULT NOW()
);

-- Payments
CREATE TABLE IF NOT EXISTS payments (
    id              SERIAL PRIMARY KEY,
    booking_ref     VARCHAR(20) REFERENCES bookings(booking_ref),
    razorpay_order  VARCHAR(100),
    razorpay_payment VARCHAR(100),
    razorpay_signature VARCHAR(200),
    amount          DECIMAL(10,2),
    status          VARCHAR(20) DEFAULT 'pending', -- pending, success, failed
    created_at      TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- Indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_bookings_phone ON bookings(phone);
CREATE INDEX IF NOT EXISTS idx_bookings_ref ON bookings(booking_ref);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_tents_class ON tents(class);
CREATE INDEX IF NOT EXISTS idx_otp_phone ON otp_store(phone);

-- ============================================
-- Seed: Tents
-- ============================================
INSERT INTO tents (name, class, location, distance, rating, reviews, price, base_price, is_surge, surge, amenities, capacity)
VALUES
    (
        'Deluxe Sangam View Tent', 'premium',
        'Sector 4, Prayagraj', 0.4, 4.8, 124,
        12500, 5000, TRUE, '2.5x',
        ARRAY['AC', 'Attached Bath', 'Meals', 'WiFi'], 2
    ),
    (
        'Premium Kumbh Camp', 'luxury',
        'Arail Ghat', 1.2, 4.6, 89,
        7200, 7200, FALSE, '',
        ARRAY['AC', 'Private Bath', 'Geyser', 'TV'], 2
    ),
    (
        'Budget Pilgrim Tent', 'basic',
        'Sector 12', 2.8, 4.1, 56,
        800, 800, FALSE, '',
        ARRAY['Common Bath', 'Meals'], 4
    ),
    (
        'VIP Maharaja Camp', 'vip',
        'Triveni Sangam', 0.1, 4.9, 210,
        45000, 15000, TRUE, '3x',
        ARRAY['AC', 'Private Bath', 'Butler', 'Meals', 'WiFi'], 2
    ),
    (
        'Standard Ganga View Camp', 'standard',
        'Naini Bridge Area', 1.8, 4.3, 67,
        2500, 2500, FALSE, '',
        ARRAY['Fan', 'Common Bath', 'Meals', 'Charging'], 3
    ),
    (
        'Luxury River View Suite', 'luxury',
        'Sangam Nose', 0.2, 4.7, 98,
        18000, 18000, FALSE, '',
        ARRAY['AC', 'Private Bath', 'Jacuzzi', 'Meals', 'WiFi', 'Butler'], 2
    ),
    (
        'Economy Seva Camp', 'basic',
        'Sector 20', 3.5, 3.9, 34,
        500, 500, FALSE, '',
        ARRAY['Common Bath', 'Drinking Water'], 6
    ),
    (
        'Royal Kumbh Pavilion', 'vip',
        'Phaphamau Ghat', 0.6, 4.9, 178,
        65000, 20000, TRUE, '3.5x',
        ARRAY['AC', 'Private Pool', 'Butler', 'Chef', 'Meals', 'WiFi', 'Spa'], 4
    )
ON CONFLICT DO NOTHING;

-- ============================================
-- Seed: Coupons
-- ============================================
INSERT INTO coupons (code, discount, description, min_amount, max_uses, expires_at)
VALUES
    ('KUMBH10', 0.10, '10% off on all bookings', 0, 500, '2027-03-31'),
    ('PILGRIM15', 0.15, '15% off for pilgrims', 2000, 200, '2027-02-28'),
    ('FIRSTKUMBH', 0.20, '20% off on first booking', 1000, 100, '2027-01-31'),
    ('MAHASNAN', 0.05, '5% off on Shahi Snan dates', 0, 1000, '2027-03-31')
ON CONFLICT DO NOTHING;
-- Vendor Payables: lets an expense be recorded as owed-but-not-yet-paid
-- (payable_status='unpaid') instead of only ever "already paid" —
-- needed to track money the business owes vendors, distinct from
-- money it has already spent.
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS vendor_name VARCHAR(200);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS payable_status VARCHAR(20) NOT NULL DEFAULT 'paid';
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'expenses_payable_status_check'
    ) THEN
        ALTER TABLE expenses ADD CONSTRAINT expenses_payable_status_check
            CHECK (payable_status IN ('paid', 'unpaid'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_expenses_payable_status ON expenses(payable_status) WHERE payable_status = 'unpaid';

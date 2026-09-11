-- ============================================
-- 016_payment_integrity.sql
-- BUG-27: nothing stopped the same Razorpay payment ID from being
-- recorded twice in `payments`. Two concurrent verifyPayment calls
-- for the same payment (a retried client request racing the
-- original, or a webhook arriving alongside the app's own call)
-- could each pass the signature check and each INSERT a 'success'
-- row before either UPDATE'd the booking, double-counting revenue
-- in every report that sums payments.status='success'.
-- ============================================

-- Only one successful record of a given Razorpay payment ID is ever
-- valid. Partial (WHERE razorpay_payment IS NOT NULL) so the many
-- 'failed' rows recorded with a NULL/blank payment id (signature
-- verification never got that far) are unaffected, and so is a
-- payment retried after a genuine gateway failure (a new attempt
-- gets its own Razorpay payment ID).
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_razorpay_payment_success
    ON payments (razorpay_payment)
    WHERE status = 'success' AND razorpay_payment IS NOT NULL AND razorpay_payment <> '';

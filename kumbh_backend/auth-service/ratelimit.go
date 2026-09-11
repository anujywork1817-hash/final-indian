package main

import "time"

// BUG-21: sendOTP, verifyOTP and adminLogin had no throttling. A
// 6-digit OTP is only 1,000,000 possibilities — trivially brute-
// forceable against verifyOTP with no attempt cap — and sendOTP
// could be hit in a loop to SMS-bomb any phone number. adminLogin
// had the same gap against admin passwords.
//
// rateLimitExceeded is DB-backed (migrations/017_rate_limits.sql),
// not an in-memory counter, so the limit holds across every
// instance behind the load balancer, not just whichever one happens
// to receive a given request.

// rateLimitExceeded atomically bumps the counter for key and
// reports whether it has now exceeded maxAttempts within window. A
// counter past its window is reset to 1 rather than accumulating
// forever.
func rateLimitExceeded(key string, maxAttempts int, window time.Duration) bool {
	// Pass the window as a plain number of seconds — Go's
	// time.Duration.String() (e.g. "15m0s") is not a format
	// Postgres's interval parser reliably accepts, but
	// `$2 * interval '1 second'` unambiguously is.
	windowSeconds := window.Seconds()

	var count int
	err := db.QueryRow(`
		INSERT INTO rate_limits (key, count, window_start)
		VALUES ($1, 1, NOW())
		ON CONFLICT (key) DO UPDATE SET
			count = CASE
				WHEN rate_limits.window_start < NOW() - ($2 * INTERVAL '1 second') THEN 1
				ELSE rate_limits.count + 1
			END,
			window_start = CASE
				WHEN rate_limits.window_start < NOW() - ($2 * INTERVAL '1 second') THEN NOW()
				ELSE rate_limits.window_start
			END
		RETURNING count
	`, key, windowSeconds).Scan(&count)
	if err != nil {
		// Fail open — a rate-limit bookkeeping problem should not
		// lock every user out of logging in.
		return false
	}
	return count > maxAttempts
}

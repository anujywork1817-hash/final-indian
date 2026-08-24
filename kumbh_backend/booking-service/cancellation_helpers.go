package main

import (
	"database/sql"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ── Timezone ─────────────────────────────────────────────
//
// All deadline math for the tiered cancellation policy uses
// IST consistently — never the device's local time (a phone in
// any timezone must see the same deadline as everyone else)
// and not bare UTC either, since check-in/check-out are
// calendar dates meant in IST. Falls back to a fixed +5:30
// offset if the IANA database is unavailable in the container
// (the tzdata package is not always installed in a minimal
// Alpine image), so behaviour never silently drifts to UTC.
var istLocation = func() *time.Location {
	if loc, err := time.LoadLocation("Asia/Kolkata"); err == nil {
		return loc
	}
	return time.FixedZone("IST", 5*60*60+30*60)
}()

// nowIST is THE clock used for every cancellation/no-show
// decision. Never call time.Now() directly elsewhere in the
// cancellation path.
func nowIST() time.Time {
	return time.Now().In(istLocation)
}

// ── Policy loading ───────────────────────────────────────

// dbQuerier is satisfied by both *sql.DB and *sql.Tx, so the
// same loader works inside a transaction (cancelBooking) and
// outside one (getRefundQuote, the no-show sweeper).
type dbQuerier interface {
	QueryRow(query string, args ...interface{}) *sql.Row
}

// loadCancellationPolicy reads the per-tent policy config. A
// missing tent (shouldn't happen — bookings always reference a
// real tent) falls back to the same safe default the column
// defaults declare, so a lookup failure never silently produces
// a stricter-than-configured policy.
func loadCancellationPolicy(q dbQuerier, tentID int) (CancellationPolicyConfig, error) {
	var p CancellationPolicyConfig
	var policyType string
	err := q.QueryRow(`
		SELECT cancellation_policy_type, free_cancellation_hours,
		       partial_refund_penalty_percent, late_cancellation_hours,
		       no_show_cutoff_hours, no_show_penalty_percent
		FROM tents WHERE id = $1
	`, tentID).Scan(
		&policyType, &p.FreeCancellationHours,
		&p.PartialRefundPenaltyPercent, &p.LateCancellationHours,
		&p.NoShowCutoffHours, &p.NoShowPenaltyPercent,
	)
	if err == sql.ErrNoRows {
		return CancellationPolicyConfig{
			PolicyType:                  PolicyFreeCancellation,
			FreeCancellationHours:       168,
			PartialRefundPenaltyPercent: 30,
			LateCancellationHours:       24,
			NoShowCutoffHours:           6,
			NoShowPenaltyPercent:        100,
		}, nil
	}
	if err != nil {
		return CancellationPolicyConfig{}, err
	}
	p.PolicyType = PolicyType(policyType)
	return p, nil
}

// nightPaiseFor derives the amount for a single night from what
// was actually paid, rather than the tent's list price — so it
// reflects any discount/surge already baked into the payment.
// Guards nights<=0 (shouldn't happen; createBooking rejects it)
// so this can never divide by zero or return a negative amount.
func nightPaiseFor(paidPaise int64, nights int) int64 {
	if nights <= 0 || paidPaise <= 0 {
		return 0
	}
	return paidPaise / int64(nights)
}

// ── Check-in tracking ─────────────────────────────────────
//
// The no-show sweeper needs to know whether a guest actually
// arrived. Nothing in the existing app recorded that, so this
// is a minimal addition: staff mark a booking checked-in at the
// gate (e.g. after scanning the e-ticket QR code — see
// e_ticket_screen.dart's "Scan at Entry Gate" flow). Once
// checked_in_at is set, the booking is permanently exempt from
// the no-show sweep.
//
// PUT /admin/bookings/:ref/check-in
func adminCheckInBooking(c *gin.Context) {
	ref := c.Param("ref")

	res, err := db.Exec(`
		UPDATE bookings SET checked_in_at = NOW(), updated_at = NOW()
		WHERE booking_ref = $1
		  AND status = 'confirmed'
		  AND checked_in_at IS NULL
	`, ref)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record check-in"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusConflict, gin.H{
			"error": "booking not found, not confirmed, or already checked in",
		})
		return
	}

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, triggered_by)
		VALUES ($1, 'CHECKED_IN', $2)
	`, ref, "admin:"+reviewerFrom(c, ""))

	c.JSON(http.StatusOK, gin.H{"message": "Checked in", "booking_ref": ref})
}

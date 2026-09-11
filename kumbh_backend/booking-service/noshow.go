package main

import (
	"database/sql"
	"fmt"
	"time"
)

// ── No-show sweeper ──────────────────────────────────────
//
// Runs alongside the existing reminder scheduler and refund
// retry worker (see main.go). Finds confirmed bookings whose
// tent-specific no-show cutoff (check-in + no_show_cutoff_hours)
// has passed with no check-in recorded, marks them 'no_show',
// and applies the no-show penalty through the SAME refund
// pipeline cancelBooking uses (insert into refunds, gate on
// approval, dispatch to the gateway) — nothing about how a
// refund is stored, retried or reconciled is reimplemented here.
func startNoShowSweeper() {
	interval := time.Duration(envFloat("NO_SHOW_SWEEP_INTERVAL_MINUTES", 15)) * time.Minute
	if interval < time.Minute {
		interval = time.Minute
	}
	fmt.Printf("👤 No-show sweeper every %s\n", interval)

	time.Sleep(45 * time.Second) // let the service finish booting first
	for {
		runIfLeader("no_show_sweeper", sweepNoShows)
		time.Sleep(interval)
	}
}

func sweepNoShows() {
	// A booking is a no-show candidate when: it is still
	// 'confirmed', nobody checked in, and this tent's no-show
	// cutoff (check-in + no_show_cutoff_hours) has passed in IST.
	rows, err := db.Query(`
		SELECT b.id, b.booking_ref, b.phone, b.tent_name, b.tent_id,
		       b.total_amount, b.nights, b.check_in, b.payment_id
		FROM bookings b
		JOIN tents t ON t.id = b.tent_id
		WHERE b.status = 'confirmed'
		  AND b.checked_in_at IS NULL
		  AND (b.check_in::timestamp + (t.no_show_cutoff_hours || ' hours')::interval)
		      < (NOW() AT TIME ZONE 'Asia/Kolkata')
		LIMIT 100
	`)
	if err != nil {
		fmt.Printf("⚠️  no-show sweep query failed: %v\n", err)
		return
	}

	type candidate struct {
		id                   int
		ref, phone, tentName string
		tentID               int
		totalAmount          float64
		nights               int
		checkIn              time.Time
		paymentID            sql.NullString
	}
	var candidates []candidate
	for rows.Next() {
		var c candidate
		if err := rows.Scan(&c.id, &c.ref, &c.phone, &c.tentName, &c.tentID,
			&c.totalAmount, &c.nights, &c.checkIn, &c.paymentID); err == nil {
			candidates = append(candidates, c)
		}
	}
	rows.Close()

	if len(candidates) == 0 {
		return
	}
	fmt.Printf("👤 sweeping %d no-show candidate(s)\n", len(candidates))

	for _, c := range candidates {
		markNoShow(c.id, c.ref, c.phone, c.tentName, c.tentID, c.totalAmount, c.nights, c.checkIn, c.paymentID)
	}
}

func markNoShow(
	bookingID int, ref, phone, tentName string, tentID int,
	totalAmount float64, nights int, checkIn time.Time, paymentID sql.NullString,
) {
	tx, err := db.Begin()
	if err != nil {
		fmt.Printf("⚠️  no-show %s: could not start transaction: %v\n", ref, err)
		return
	}
	defer tx.Rollback()

	// Re-check status under lock — another request (a user
	// cancelling in the same window, or a concurrent sweep
	// cycle) may have already moved this booking on.
	var status string
	var checkedInAt sql.NullTime
	err = tx.QueryRow(`
		SELECT status, checked_in_at FROM bookings WHERE id = $1 FOR UPDATE
	`, bookingID).Scan(&status, &checkedInAt)
	if err != nil || status != "confirmed" || checkedInAt.Valid {
		return
	}

	policy, perr := loadCancellationPolicy(tx, tentID)
	if perr != nil {
		fmt.Printf("⚠️  no-show %s: could not load policy: %v\n", ref, perr)
		return
	}

	paidPaise := paidAmountPaise(ref, status, totalAmount, paymentID)
	result := calculateNoShowRefund(paidPaise, policy)

	if _, err = tx.Exec(`
		UPDATE bookings SET status = 'no_show', cancelled_at = NOW(), updated_at = NOW()
		WHERE id = $1
	`, bookingID); err != nil {
		fmt.Printf("⚠️  no-show %s: could not update status: %v\n", ref, err)
		return
	}

	refundStatus := "pending"
	if refundPolicy.RequireApproval {
		refundStatus = "awaiting_approval"
	}
	gatewayPayment := ""
	switch {
	case result.RefundAmountPaise <= 0:
		refundStatus = "not_applicable"
	case !paymentID.Valid || paymentID.String == "" || paymentID.String == "CASH":
		if !refundPolicy.RequireApproval {
			refundStatus = "manual"
		}
	default:
		gatewayPayment = paymentID.String
	}

	var refundID int
	err = tx.QueryRow(`
		INSERT INTO refunds (
			booking_ref, phone, tent_name, check_in,
			razorpay_payment_id,
			booking_amount_paise, refund_amount_paise, fee_paise,
			policy_rule, policy_percent, status, idempotency_key,
			requested_at
		) VALUES ($1,$2,$3,$4,NULLIF($5,''),$6,$7,0,$8,$9,$10,$11,NOW())
		ON CONFLICT (booking_ref) DO NOTHING
		RETURNING id
	`,
		ref, phone, tentName, checkIn,
		gatewayPayment,
		paidPaise, result.RefundAmountPaise,
		result.TierApplied, result.RefundPercent, refundStatus,
		fmt.Sprintf("refund_%s", ref),
	).Scan(&refundID)

	alreadyExisted := err == sql.ErrNoRows
	if err != nil && !alreadyExisted {
		fmt.Printf("⚠️  no-show %s: could not record refund: %v\n", ref, err)
		return
	}

	if !alreadyExisted {
		tx.Exec(`
			INSERT INTO refund_audit_log
				(booking_ref, event, tier_applied, refund_amount_paise, penalty_amount_paise, triggered_by)
			VALUES ($1,'NO_SHOW',$2,$3,$4,'system:no_show_sweeper')
		`, ref, result.TierApplied, result.RefundAmountPaise, result.PenaltyAmountPaise)
	}

	if err = tx.Commit(); err != nil {
		fmt.Printf("⚠️  no-show %s: commit failed: %v\n", ref, err)
		return
	}

	fmt.Printf("👤 %s marked NO_SHOW — refund ₹%.2f (%s)\n",
		ref, float64(result.RefundAmountPaise)/100, result.TierApplied)

	if refundStatus == "pending" && !alreadyExisted {
		go executeRefund(refundID)
	}
}

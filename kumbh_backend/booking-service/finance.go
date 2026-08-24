package main

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ── Admin Finance & Accounting — Phase 1 ─────────────────
//
// Foundation only: real bookings/payments/refunds data, surfaced
// as dashboard totals and a per-booking breakdown. Operating
// Expenses and Payment Gateway Charges are not tracked anywhere
// in the system yet (that's Phase 3 and Phase 4 of the finance
// module) — those two cards report 0 with an explicit "not yet
// tracked" flag rather than a fabricated number, so the UI never
// implies a number exists that doesn't.
//
// Money-in definitions used here:
//   Gross Booking Value — SUM(total_amount) over every booking
//     that ever became real (i.e. not still 'pending' with no
//     payment attached). Cancelled/no-show bookings still count
//     here; the Refunds card is what nets them down, matching
//     the pipeline: Gross Booking Value − Refunds = Net Sales.
//   Amount Received     — SUM of successful gateway payments,
//     plus cash bookings actually confirmed at the tent.
//   Outstanding          — Gross − Received − Refunds, floored at
//     0. This is a Phase 1 approximation: today every booking is
//     paid in full up front (online or cash), so there is no
//     partial-payment case yet — that lands with the Customer
//     Payment Tracking module (Phase 2).
//   Refunds              — settled (status='succeeded') refunds
//     only, i.e. money that has actually left the account.

// GET /admin/finance/dashboard
func adminFinanceDashboard(c *gin.Context) {
	var totalBookings int
	var grossPaise, receivedGatewayPaise, receivedCashPaise, refundedPaise int64

	db.QueryRow(`SELECT COUNT(*) FROM bookings`).Scan(&totalBookings)

	db.QueryRow(`
		SELECT COALESCE(SUM(total_amount * 100), 0)::BIGINT
		FROM bookings WHERE status != 'pending'
	`).Scan(&grossPaise)

	db.QueryRow(`
		SELECT COALESCE(SUM(amount * 100), 0)::BIGINT
		FROM payments WHERE status = 'success'
	`).Scan(&receivedGatewayPaise)

	db.QueryRow(`
		SELECT COALESCE(SUM(total_amount * 100), 0)::BIGINT
		FROM bookings
		WHERE payment_id = 'CASH' AND status IN ('confirmed','completed','checked_in','no_show')
	`).Scan(&receivedCashPaise)

	db.QueryRow(`
		SELECT COALESCE(SUM(refund_amount_paise), 0)
		FROM refunds WHERE status = 'succeeded'
	`).Scan(&refundedPaise)

	receivedPaise := receivedGatewayPaise + receivedCashPaise
	outstandingPaise := grossPaise - receivedPaise - refundedPaise
	if outstandingPaise < 0 {
		outstandingPaise = 0
	}

	// Operating Expenses — real as of Phase 3. Net of any
	// reversal rows (a reversal is a negative-amount row, so a
	// plain SUM already nets it out without special-casing).
	var operatingExpensesPaise int64
	db.QueryRow(`
		SELECT COALESCE(SUM((amount + tax) * 100), 0)::BIGINT FROM expenses
	`).Scan(&operatingExpensesPaise)

	// Gateway Charges — real as of Phase 4. Fee is computed per
	// successful payment against that payment's gateway's
	// fee_percent/tax_on_fee_percent (gatewayFeePaiseFor), not a
	// flat rate, since different gateways/modes carry different
	// commercial terms.
	var gatewayChargesPaise int64
	rows, err := db.Query(`SELECT amount, payment_mode FROM payments WHERE status = 'success'`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var amount float64
			var mode string
			if rows.Scan(&amount, &mode) == nil {
				gatewayChargesPaise += gatewayFeePaiseFor(mode, int64(amount*100+0.5))
			}
		}
	}

	netRevenuePaise := receivedPaise - refundedPaise - gatewayChargesPaise
	operatingProfitPaise := netRevenuePaise - operatingExpensesPaise

	c.JSON(http.StatusOK, gin.H{
		"total_bookings":       totalBookings,
		"gross_booking_value":  float64(grossPaise) / 100.0,
		"amount_received":      float64(receivedPaise) / 100.0,
		"outstanding":          float64(outstandingPaise) / 100.0,
		"refunds":              float64(refundedPaise) / 100.0,
		"operating_expenses":   float64(operatingExpensesPaise) / 100.0,
		"gateway_charges":      float64(gatewayChargesPaise) / 100.0,
		"net_revenue":          float64(netRevenuePaise) / 100.0,
		"operating_profit":     float64(operatingProfitPaise) / 100.0,
		"expenses_tracked":     true, // Phase 3
		"gateway_fees_tracked": true, // Phase 4
	})
}

// GET /admin/finance/bookings/:ref/accounting
//
// Per-booking drill-down for the "Accounting Details" button.
func adminBookingAccounting(c *gin.Context) {
	ref := c.Param("ref")

	var (
		phone, tentName, status string
		guestName               sql.NullString
		totalAmount             float64
		country                 string
	)
	err := db.QueryRow(`
		SELECT b.phone, b.tent_name, b.status, b.guest_name, b.total_amount,
		       COALESCE(u.country, 'India')
		FROM bookings b
		LEFT JOIN users u ON u.phone = b.phone
		WHERE b.booking_ref = $1
	`, ref).Scan(&phone, &tentName, &status, &guestName, &totalAmount, &country)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load booking"})
		return
	}

	var paymentID sql.NullString
	db.QueryRow(`SELECT payment_id FROM bookings WHERE booking_ref = $1`, ref).Scan(&paymentID)
	paidPaise := paidAmountPaise(ref, status, totalAmount, paymentID)

	var refundAmountPaise int64
	var refundStatus string
	var refundApprovalReason, refundRejectionReason, refundReviewedBy sql.NullString
	db.QueryRow(`
		SELECT refund_amount_paise, status, approval_reason, rejection_reason, reviewed_by
		FROM refunds WHERE booking_ref = $1
	`, ref).Scan(&refundAmountPaise, &refundStatus, &refundApprovalReason, &refundRejectionReason, &refundReviewedBy)

	totalPaise := int64(totalAmount*100 + 0.5)
	outstandingPaise := totalPaise - paidPaise - refundAmountPaise
	if outstandingPaise < 0 || status == "cancelled" || status == "no_show" {
		outstandingPaise = 0
	}

	customerName := guestName.String
	if customerName == "" {
		customerName = phone
	}

	c.JSON(http.StatusOK, gin.H{
		"booking_ref":    ref,
		"customer":       customerName,
		"phone":          phone,
		"country":        country,
		"tent_name":      tentName,
		"status":         status,
		"payment_status": paymentStatusFor(status, totalPaise, paidPaise, refundAmountPaise),
		"booking_value":  totalAmount,
		"paid":           float64(paidPaise) / 100.0,
		"outstanding":    float64(outstandingPaise) / 100.0,
		"refund_amount":  float64(refundAmountPaise) / 100.0,
		"refund_status":  refundStatus,
		// Why the money moved, not just that it did — the accounting
		// view should answer that without a second lookup.
		"refund_approval_reason":  refundApprovalReason.String,
		"refund_rejection_reason": refundRejectionReason.String,
		"refund_reviewed_by":      refundReviewedBy.String,
		"gateway_charges":         0.0, // not tracked until Phase 4
	})
}

// GET /admin/finance/bookings/:ref/audit-log
//
// The append-only trail behind "fully logged" — every
// cancellation, no-show, refund-workflow transition, and manual
// payment recorded against this booking, in order. Support/
// disputes look here, not at the mutable `refunds` row.
func adminBookingAuditLog(c *gin.Context) {
	ref := c.Param("ref")

	rows, err := db.Query(`
		SELECT event, COALESCE(tier_applied,''), refund_amount_paise, penalty_amount_paise,
		       triggered_by, COALESCE(note,''), created_at
		FROM refund_audit_log
		WHERE booking_ref = $1
		ORDER BY created_at ASC
	`, ref)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch audit log"})
		return
	}
	defer rows.Close()

	type entry struct {
		Event         string  `json:"event"`
		TierApplied   string  `json:"tier_applied,omitempty"`
		RefundAmount  float64 `json:"amount"`
		PenaltyAmount float64 `json:"penalty_amount"`
		TriggeredBy   string  `json:"triggered_by"`
		Note          string  `json:"note,omitempty"`
		CreatedAt     string  `json:"created_at"`
	}
	entries := []entry{}
	for rows.Next() {
		var e entry
		var amountPaise, penaltyPaise sql.NullInt64
		var ts sql.NullTime
		if err := rows.Scan(&e.Event, &e.TierApplied, &amountPaise, &penaltyPaise, &e.TriggeredBy, &e.Note, &ts); err == nil {
			if amountPaise.Valid {
				e.RefundAmount = float64(amountPaise.Int64) / 100.0
			}
			if penaltyPaise.Valid {
				e.PenaltyAmount = float64(penaltyPaise.Int64) / 100.0
			}
			if ts.Valid {
				e.CreatedAt = ts.Time.Format("2006-01-02 15:04:05")
			}
			entries = append(entries, e)
		}
	}

	c.JSON(http.StatusOK, gin.H{"booking_ref": ref, "audit_log": entries})
}

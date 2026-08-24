package main

import (
	"database/sql"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ── Admin Finance & Accounting — Phase 2 ─────────────────
//
// Revenue Summary + Customer Payment Tracking + (audit logging
// for) the Refund workflow. Builds on Phase 1's dashboard/
// accounting endpoints in finance.go, and reuses the existing
// refund pipeline (refunds.go) rather than introducing a second
// one — Phase 2 only adds the ability to RECORD a manual/partial
// payment and to REPORT on payment/revenue state; it does not
// change how refunds are decided or dispatched.

// paymentStatusFor derives the Paid/Partial/Pending/Refunded/
// Cancelled tag from raw amounts. Centralized here so the
// dashboard, the per-booking accounting view, and the payment
// tracking list can never disagree on what "Partial" means.
func paymentStatusFor(bookingStatus string, totalPaise, paidPaise, refundedPaise int64) string {
	if bookingStatus == "cancelled" || bookingStatus == "no_show" {
		if refundedPaise > 0 {
			return "Refunded"
		}
		return "Cancelled"
	}
	if paidPaise <= 0 {
		return "Pending"
	}
	if paidPaise < totalPaise {
		return "Partial"
	}
	return "Paid"
}

// ── Customer Payment Tracking ────────────────────────────

type paymentTrackingRow struct {
	BookingRef    string  `json:"booking_ref"`
	Customer      string  `json:"customer"`
	Phone         string  `json:"phone"`
	TentName      string  `json:"tent_name"`
	BookingStatus string  `json:"booking_status"`
	TotalValue    float64 `json:"total_value"`
	Received      float64 `json:"received"`
	Pending       float64 `json:"pending"`
	RefundAmount  float64 `json:"refund_processed"`
	Status        string  `json:"status"`
}

// GET /admin/payments — every booking's payment state, for the
// Customer Payment Tracking screen.
func adminPaymentTracking(c *gin.Context) {
	rows, err := db.Query(`
		SELECT b.booking_ref, COALESCE(b.guest_name,''), b.phone, b.tent_name,
		       b.status, b.total_amount, b.payment_id
		FROM bookings b
		ORDER BY b.created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	defer rows.Close()

	type raw struct {
		ref, guestName, phone, tentName, status string
		total                                   float64
		paymentID                               sql.NullString
	}
	var all []raw
	for rows.Next() {
		var r raw
		if err := rows.Scan(&r.ref, &r.guestName, &r.phone, &r.tentName, &r.status, &r.total, &r.paymentID); err == nil {
			all = append(all, r)
		}
	}

	result := make([]paymentTrackingRow, 0, len(all))
	var totalReceivedPaise, totalPendingPaise, totalRefundedPaise int64
	statusCounts := map[string]int{}

	for _, r := range all {
		paidPaise := paidAmountPaise(r.ref, r.status, r.total, r.paymentID)
		totalPaise := int64(r.total*100 + 0.5)

		var refundedPaise int64
		db.QueryRow(`
			SELECT refund_amount_paise FROM refunds WHERE booking_ref = $1 AND status = 'succeeded'
		`, r.ref).Scan(&refundedPaise)

		pendingPaise := totalPaise - paidPaise
		if pendingPaise < 0 || r.status == "cancelled" || r.status == "no_show" {
			pendingPaise = 0
		}

		status := paymentStatusFor(r.status, totalPaise, paidPaise, refundedPaise)
		statusCounts[status]++

		customer := r.guestName
		if customer == "" {
			customer = r.phone
		}

		result = append(result, paymentTrackingRow{
			BookingRef:    r.ref,
			Customer:      customer,
			Phone:         r.phone,
			TentName:      r.tentName,
			BookingStatus: r.status,
			TotalValue:    r.total,
			Received:      float64(paidPaise) / 100.0,
			Pending:       float64(pendingPaise) / 100.0,
			RefundAmount:  float64(refundedPaise) / 100.0,
			Status:        status,
		})

		totalReceivedPaise += paidPaise
		totalPendingPaise += pendingPaise
		totalRefundedPaise += refundedPaise
	}

	c.JSON(http.StatusOK, gin.H{
		"payments":       result,
		"total":          len(result),
		"total_received": float64(totalReceivedPaise) / 100.0,
		"total_pending":  float64(totalPendingPaise) / 100.0,
		"total_refunded": float64(totalRefundedPaise) / 100.0,
		"status_counts":  statusCounts,
	})
}

// POST /admin/bookings/:ref/payments
//
// Records a manual payment (cash / UPI / card / bank transfer
// taken outside the Razorpay flow) against a booking — including
// a PARTIAL amount. This is what makes "Partial" a reachable,
// testable state: today only cash/manual payments can be partial
// since the Razorpay checkout always collects the full amount in
// one shot.
func adminRecordPayment(c *gin.Context) {
	ref := c.Param("ref")

	var req struct {
		Amount        float64 `json:"amount" binding:"required"`
		PaymentMode   string  `json:"payment_mode" binding:"required"`
		TransactionID string  `json:"transaction_id"`
		Note          string  `json:"note"`
		RecordedBy    string  `json:"recorded_by"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "amount must be positive"})
		return
	}
	mode := strings.ToLower(strings.TrimSpace(req.PaymentMode))
	validModes := map[string]bool{"cash": true, "upi": true, "card": true, "bank_transfer": true, "other": true}
	if !validModes[mode] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment_mode"})
		return
	}
	recordedBy := strings.TrimSpace(req.RecordedBy)
	if recordedBy == "" {
		if v := strings.TrimSpace(c.GetHeader("X-Admin-Username")); v != "" {
			recordedBy = v
		} else {
			recordedBy = "unknown-admin"
		}
	}

	var status, phone string
	var totalAmount float64
	err := db.QueryRow(`
		SELECT status, phone, total_amount FROM bookings WHERE booking_ref = $1
	`, ref).Scan(&status, &phone, &totalAmount)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch booking"})
		return
	}
	if status == "cancelled" || status == "no_show" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot record a payment against a cancelled/no-show booking"})
		return
	}

	// A payment can never push the total received above what was
	// actually booked — the same over-payment guard the refunds
	// table enforces on the other side of the ledger.
	var paymentID sql.NullString
	db.QueryRow(`SELECT payment_id FROM bookings WHERE booking_ref = $1`, ref).Scan(&paymentID)
	alreadyPaidPaise := paidAmountPaise(ref, status, totalAmount, paymentID)
	totalPaise := int64(totalAmount*100 + 0.5)
	newAmountPaise := int64(req.Amount*100 + 0.5)
	if alreadyPaidPaise+newAmountPaise > totalPaise {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":         "amount exceeds outstanding balance",
			"already_paid":  float64(alreadyPaidPaise) / 100.0,
			"booking_value": totalAmount,
		})
		return
	}

	var paymentRowID int
	err = db.QueryRow(`
		INSERT INTO payments
			(booking_ref, amount, status, payment_mode, transaction_id, recorded_by, note)
		VALUES ($1, $2, 'success', $3, NULLIF($4,''), $5, NULLIF($6,''))
		RETURNING id
	`, ref, req.Amount, mode, req.TransactionID, recordedBy, req.Note).Scan(&paymentRowID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record payment: " + err.Error()})
		return
	}

	newPaidPaise := alreadyPaidPaise + newAmountPaise
	newStatus := paymentStatusFor(status, totalPaise, newPaidPaise, 0)

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, refund_amount_paise, triggered_by, note)
		VALUES ($1, 'PAYMENT_RECORDED', $2, $3, $4)
	`, ref, newAmountPaise, "admin:"+recordedBy,
		"payment_mode="+mode+" txn="+req.TransactionID)

	go postLedgerPair(
		time.Now().Format("2006-01-02"), "booking_payment", ref,
		bankAccountFor(mode), "Customer/Revenue", req.Amount,
		fmt.Sprintf("%s payment recorded by %s", mode, recordedBy),
	)

	c.JSON(http.StatusCreated, gin.H{
		"message":        "Payment recorded",
		"booking_ref":    ref,
		"payment_id":     paymentRowID,
		"amount":         req.Amount,
		"payment_mode":   mode,
		"total_received": float64(newPaidPaise) / 100.0,
		"payment_status": newStatus,
	})
}

// ── Customer Receivables ─────────────────────────────────
//
// The Payments screen (adminPaymentTracking) shows every booking's
// payment state; this is the accounts-receivable-focused view of
// the same underlying numbers — only bookings with money still
// owed, bucketed by how long it's been outstanding (aging), which
// is what a collections follow-up actually needs.
func adminCustomerReceivables(c *gin.Context) {
	rows, err := db.Query(`
		SELECT b.booking_ref, COALESCE(b.guest_name,''), b.phone, b.tent_name,
		       b.status, b.total_amount, b.payment_id, b.created_at
		FROM bookings b
		WHERE b.status NOT IN ('cancelled', 'no_show')
		ORDER BY b.created_at ASC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	defer rows.Close()

	type receivableRow struct {
		BookingRef  string  `json:"booking_ref"`
		Customer    string  `json:"customer"`
		Phone       string  `json:"phone"`
		TentName    string  `json:"tent_name"`
		TotalValue  float64 `json:"total_value"`
		Received    float64 `json:"received"`
		Due         float64 `json:"due"`
		DaysOld     int     `json:"days_outstanding"`
		AgingBucket string  `json:"aging_bucket"`
		BookedAt    string  `json:"booked_at"`
	}

	out := []receivableRow{}
	var totalDuePaise int64
	bucketTotals := map[string]float64{"0-7 days": 0, "8-30 days": 0, "31+ days": 0}
	now := time.Now()

	for rows.Next() {
		var ref, guestName, phone, tentName, status string
		var total float64
		var paymentID sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&ref, &guestName, &phone, &tentName, &status, &total, &paymentID, &createdAt); err != nil {
			continue
		}

		paidPaise := paidAmountPaise(ref, status, total, paymentID)
		totalPaise := int64(total*100 + 0.5)
		duePaise := totalPaise - paidPaise
		if duePaise <= 0 {
			continue // fully paid — not a receivable
		}

		daysOld := int(now.Sub(createdAt).Hours() / 24)
		bucket := "0-7 days"
		if daysOld > 30 {
			bucket = "31+ days"
		} else if daysOld > 7 {
			bucket = "8-30 days"
		}

		customer := guestName
		if customer == "" {
			customer = phone
		}

		duRupees := float64(duePaise) / 100.0
		out = append(out, receivableRow{
			BookingRef: ref, Customer: customer, Phone: phone, TentName: tentName,
			TotalValue: total, Received: float64(paidPaise) / 100.0, Due: duRupees,
			DaysOld: daysOld, AgingBucket: bucket, BookedAt: createdAt.Format("2006-01-02"),
		})
		totalDuePaise += duePaise
		bucketTotals[bucket] += duRupees
	}

	c.JSON(http.StatusOK, gin.H{
		"receivables":   out,
		"total":         len(out),
		"total_due":     float64(totalDuePaise) / 100.0,
		"aging_buckets": bucketTotals,
	})
}

// ── Revenue Summary ───────────────────────────────────────

// GET /admin/revenue/summary?group_by=month|country|tent|booking
//
// Gross Booking Value → (−) GST (pass-through, shown separately,
// excluded from Net Sales) → (−) Refunds → = Net Sales.
// Cancelled bookings are counted and valued separately so they
// never inflate revenue.
func adminRevenueSummary(c *gin.Context) {
	groupBy := c.DefaultQuery("group_by", "month")

	var groupExpr, groupLabel string
	switch groupBy {
	case "country":
		groupExpr = "COALESCE(u.country, 'India')"
		groupLabel = "country"
	case "tent":
		groupExpr = "b.tent_name"
		groupLabel = "tent"
	case "booking":
		groupExpr = "b.booking_ref"
		groupLabel = "booking_ref"
	default:
		groupBy = "month"
		groupExpr = "TO_CHAR(b.created_at, 'YYYY-MM')"
		groupLabel = "month"
	}

	query := `
		SELECT ` + groupExpr + ` AS grp,
		       COUNT(*) FILTER (WHERE b.status != 'cancelled')                    AS booking_count,
		       COALESCE(SUM(b.total_amount)     FILTER (WHERE b.status != 'cancelled' AND b.status != 'pending'), 0) AS gross_value,
		       COALESCE(SUM(b.tax)              FILTER (WHERE b.status != 'cancelled' AND b.status != 'pending'), 0) AS gst_collected,
		       COUNT(*) FILTER (WHERE b.status = 'cancelled')                     AS cancelled_count,
		       COALESCE(SUM(b.total_amount) FILTER (WHERE b.status = 'cancelled'), 0) AS cancelled_value
		FROM bookings b
		LEFT JOIN users u ON u.phone = b.phone
		GROUP BY grp
		ORDER BY grp DESC
	`
	rows, err := db.Query(query)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to compute revenue summary: " + err.Error()})
		return
	}
	defer rows.Close()

	type row struct {
		Group          string  `json:"group"`
		BookingCount   int     `json:"booking_count"`
		GrossValue     float64 `json:"gross_booking_value"`
		GSTCollected   float64 `json:"gst_collected"`
		Refunds        float64 `json:"refunds"`
		NetSales       float64 `json:"net_sales"`
		CancelledCount int     `json:"cancelled_count"`
		CancelledValue float64 `json:"cancelled_value"`
	}

	var out []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.Group, &r.BookingCount, &r.GrossValue, &r.GSTCollected, &r.CancelledCount, &r.CancelledValue); err != nil {
			continue
		}
		out = append(out, r)
	}
	if out == nil {
		out = []row{}
	}

	// Refunds don't share a clean GROUP BY key with the query
	// above for every dimension (a refund belongs to one booking,
	// which belongs to one tent/country/month) — computed per row
	// with a second pass rather than a second, differently-shaped
	// query per group_by value.
	for i := range out {
		var refundSum sql.NullFloat64
		switch groupBy {
		case "country":
			db.QueryRow(`
				SELECT SUM(r.refund_amount_paise)/100.0 FROM refunds r
				JOIN bookings b ON b.booking_ref = r.booking_ref
				LEFT JOIN users u ON u.phone = b.phone
				WHERE COALESCE(u.country,'India') = $1 AND r.status = 'succeeded'
			`, out[i].Group).Scan(&refundSum)
		case "tent":
			db.QueryRow(`
				SELECT SUM(refund_amount_paise)/100.0 FROM refunds
				WHERE tent_name = $1 AND status = 'succeeded'
			`, out[i].Group).Scan(&refundSum)
		case "booking":
			db.QueryRow(`
				SELECT SUM(refund_amount_paise)/100.0 FROM refunds
				WHERE booking_ref = $1 AND status = 'succeeded'
			`, out[i].Group).Scan(&refundSum)
		default: // month
			db.QueryRow(`
				SELECT SUM(r.refund_amount_paise)/100.0 FROM refunds r
				WHERE TO_CHAR(r.created_at, 'YYYY-MM') = $1 AND r.status = 'succeeded'
			`, out[i].Group).Scan(&refundSum)
		}
		if refundSum.Valid {
			out[i].Refunds = refundSum.Float64
		}
		out[i].NetSales = (out[i].GrossValue - out[i].GSTCollected) - out[i].Refunds
	}

	c.JSON(http.StatusOK, gin.H{
		"group_by": groupLabel,
		"rows":     out,
	})
}

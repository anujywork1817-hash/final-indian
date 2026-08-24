package main

import (
	"database/sql"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// ── Payment Gateway Settlement & Reconciliation — Phase 4 ──
//
// The highest-risk control in the accounting module: catching a
// booking whose gateway record and bank deposit don't agree
// BEFORE it becomes a silent loss. There is no live Razorpay
// Settlement API/webhook wired up (no public HTTPS endpoint
// exists for this deployment), so "bank settlement" here means
// what an accountant enters after reading the actual bank
// statement — never a number this code invents on its own.
//
// Reconciliation only covers gateway (Razorpay) payments. A
// cash/UPI/card/bank_transfer payment recorded manually (Phase
// 2) is money already in hand, not a gateway settlement waiting
// to land in the bank — there is nothing to reconcile it against.

const reconciliationTolerancePaise = 100 // ₹1 — absorbs paisa-level rounding, nothing more

// reconcileStatus is the three-way match, kept pure and DB-free
// so every branch is directly unit-testable.
//
//   - "pending"  — no gateway payment recorded for this booking yet
//   - "mismatch" — the gateway record itself doesn't match the
//     booking amount (leg 1 fails) — this is checked FIRST and
//     wins over everything else, since it's the more serious error
//   - "partial"  — gateway leg is fine, but no bank settlement has
//     been recorded yet (nothing to compare against)
//   - "matched"  — gateway leg is fine AND the recorded bank
//     settlement equals gross collection minus gateway fee (and
//     tax on that fee), within a ₹1 rounding tolerance
//   - "mismatch" — bank settlement was recorded but doesn't match
//     the expected net (the case the acceptance criteria names
//     explicitly)
func reconcileStatus(
	bookingAmountPaise, gatewayAmountPaise int64, hasGatewayPayment bool,
	gatewayFeePaise int64, bankSettledPaise int64, hasBankSettlement bool,
) string {
	if !hasGatewayPayment {
		return "pending"
	}
	if bookingAmountPaise != gatewayAmountPaise {
		return "mismatch"
	}
	if !hasBankSettlement {
		return "partial"
	}
	expectedNetPaise := gatewayAmountPaise - gatewayFeePaise
	diff := bankSettledPaise - expectedNetPaise
	if diff < 0 {
		diff = -diff
	}
	if diff > reconciliationTolerancePaise {
		return "mismatch"
	}
	return "matched"
}

func gatewayFeePaiseFor(gateway string, grossPaise int64) int64 {
	var feePct, taxPct float64
	err := db.QueryRow(`
		SELECT fee_percent, tax_on_fee_percent FROM gateway_settings WHERE gateway = $1
	`, gateway).Scan(&feePct, &taxPct)
	if err != nil {
		return 0
	}
	fee := float64(grossPaise) * (feePct / 100.0)
	taxOnFee := fee * (taxPct / 100.0)
	return int64(fee + taxOnFee + 0.5)
}

// ── Payment Gateway Summary ──────────────────────────────

// GET /admin/gateway-summary
func adminGatewaySummary(c *gin.Context) {
	rows, err := db.Query(`
		SELECT payment_mode,
		       COUNT(*) FILTER (WHERE status = 'success'),
		       COALESCE(SUM(amount) FILTER (WHERE status = 'success'), 0),
		       COUNT(*) FILTER (WHERE status = 'failed'),
		       COALESCE(SUM(amount) FILTER (WHERE status = 'failed'), 0)
		FROM payments
		GROUP BY payment_mode
		ORDER BY payment_mode
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to compute gateway summary"})
		return
	}
	defer rows.Close()

	type providerSummary struct {
		Gateway            string  `json:"gateway"`
		Transactions       int     `json:"transactions"`
		GrossCollection    float64 `json:"gross_collection"`
		GatewayFee         float64 `json:"gateway_fee"`
		TaxOnFee           float64 `json:"tax_on_fee"`
		NetSettlement      float64 `json:"net_settlement"`
		FailedTransactions int     `json:"failed_transactions"`
		FailedAmount       float64 `json:"failed_amount"`
	}

	out := []providerSummary{}
	for rows.Next() {
		var p providerSummary
		var grossPaise int64
		var grossRupees, failedAmount float64
		if err := rows.Scan(&p.Gateway, &p.Transactions, &grossRupees, &p.FailedTransactions, &failedAmount); err != nil {
			continue
		}
		grossPaise = int64(grossRupees*100 + 0.5)

		var feePct, taxPct float64
		db.QueryRow(`SELECT fee_percent, tax_on_fee_percent FROM gateway_settings WHERE gateway = $1`, p.Gateway).Scan(&feePct, &taxPct)
		feePaise := int64(float64(grossPaise) * (feePct / 100.0))
		taxPaise := int64(float64(feePaise) * (taxPct / 100.0))

		p.GrossCollection = grossRupees
		p.GatewayFee = float64(feePaise) / 100.0
		p.TaxOnFee = float64(taxPaise) / 100.0
		p.NetSettlement = grossRupees - p.GatewayFee - p.TaxOnFee
		p.FailedAmount = failedAmount
		out = append(out, p)
	}

	c.JSON(http.StatusOK, gin.H{"providers": out})
}

// ── Three-way reconciliation ─────────────────────────────

type reconciliationRow struct {
	BookingRef    string  `json:"booking_ref"`
	Gateway       string  `json:"gateway"`
	BookingAmount float64 `json:"booking_amount"`
	GatewayAmount float64 `json:"gateway_amount"`
	// FeeAndTax bundles the gateway fee AND tax on that fee — the
	// two are split out separately in adminGatewaySummary, but
	// here only their combined deduction from gross matters for
	// the match/mismatch decision.
	FeeAndTax         float64 `json:"gateway_fee_and_tax"`
	ExpectedNet       float64 `json:"expected_net_settlement"`
	BankSettledAmount float64 `json:"bank_settled_amount"`
	SettlementID      string  `json:"settlement_id,omitempty"`
	SettlementDate    string  `json:"settlement_date,omitempty"`
	Status            string  `json:"status"` // pending | partial | matched | mismatch
}

func buildReconciliationRows() ([]reconciliationRow, error) {
	// Scope to bookings with at least one successful gateway
	// (Razorpay) payment — cash/manual payments have nothing to
	// reconcile against a bank settlement.
	rows, err := db.Query(`
		SELECT b.booking_ref, b.total_amount, p.amount, p.payment_mode
		FROM bookings b
		JOIN payments p ON p.booking_ref = b.booking_ref
		WHERE p.status = 'success' AND p.payment_mode = 'razorpay'
		ORDER BY b.created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []reconciliationRow{}
	for rows.Next() {
		var ref, gateway string
		var bookingAmount, gatewayAmount float64
		if err := rows.Scan(&ref, &bookingAmount, &gatewayAmount, &gateway); err != nil {
			continue
		}

		bookingPaise := int64(bookingAmount*100 + 0.5)
		gatewayPaise := int64(gatewayAmount*100 + 0.5)
		feePaise := gatewayFeePaiseFor(gateway, gatewayPaise)

		var settledAmount sql.NullFloat64
		var settlementID sql.NullString
		var settlementDate sql.NullTime
		hasBank := db.QueryRow(`
			SELECT amount, settlement_id, settlement_date FROM bank_settlements WHERE booking_ref = $1
		`, ref).Scan(&settledAmount, &settlementID, &settlementDate) == nil

		var bankPaise int64
		if hasBank {
			bankPaise = int64(settledAmount.Float64*100 + 0.5)
		}

		status := reconcileStatus(bookingPaise, gatewayPaise, true, feePaise, bankPaise, hasBank)

		r := reconciliationRow{
			BookingRef:    ref,
			Gateway:       gateway,
			BookingAmount: bookingAmount,
			GatewayAmount: gatewayAmount,
			FeeAndTax:     float64(feePaise) / 100.0,
			ExpectedNet:   float64(gatewayPaise-feePaise) / 100.0,
			Status:        status,
		}
		if hasBank {
			r.BankSettledAmount = settledAmount.Float64
			if settlementID.Valid {
				r.SettlementID = settlementID.String
			}
			if settlementDate.Valid {
				r.SettlementDate = settlementDate.Time.Format("2006-01-02")
			}
		}
		out = append(out, r)
	}
	return out, nil
}

// GET /admin/reconciliation
func adminReconciliation(c *gin.Context) {
	rows, err := buildReconciliationRows()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to build reconciliation"})
		return
	}
	counts := map[string]int{}
	for _, r := range rows {
		counts[r.Status]++
	}
	c.JSON(http.StatusOK, gin.H{"reconciliation": rows, "total": len(rows), "status_counts": counts})
}

// GET /admin/reconciliation/exceptions
//
// The actionable alert queue — mismatches only. A mismatch is
// never just a red dot in a table; it has to be something staff
// can pull up and act on, so this is its own endpoint rather than
// a client-side filter of the full list.
func adminReconciliationExceptions(c *gin.Context) {
	rows, err := buildReconciliationRows()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to build reconciliation"})
		return
	}
	exceptions := make([]reconciliationRow, 0)
	for _, r := range rows {
		if r.Status == "mismatch" {
			exceptions = append(exceptions, r)
		}
	}
	c.JSON(http.StatusOK, gin.H{"exceptions": exceptions, "total": len(exceptions)})
}

// POST /admin/bookings/:ref/bank-settlement
func adminRecordBankSettlement(c *gin.Context) {
	ref := c.Param("ref")

	var req struct {
		Gateway        string  `json:"gateway"`
		SettlementID   string  `json:"settlement_id"`
		SettlementDate string  `json:"settlement_date" binding:"required"`
		Amount         float64 `json:"amount" binding:"required"`
		RecordedBy     string  `json:"recorded_by" binding:"required"`
		Note           string  `json:"note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "amount must be positive"})
		return
	}
	gateway := strings.ToLower(strings.TrimSpace(req.Gateway))
	if gateway == "" {
		gateway = "razorpay"
	}

	var exists bool
	db.QueryRow(`SELECT EXISTS(SELECT 1 FROM bookings WHERE booking_ref = $1)`, ref).Scan(&exists)
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	var id int
	err := db.QueryRow(`
		INSERT INTO bank_settlements
			(booking_ref, gateway, settlement_id, settlement_date, amount, recorded_by, note)
		VALUES ($1,$2,NULLIF($3,''),$4,$5,$6,NULLIF($7,''))
		RETURNING id
	`, ref, gateway, req.SettlementID, req.SettlementDate, req.Amount,
		strings.TrimSpace(req.RecordedBy), req.Note,
	).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "uq_bank_settlements_booking_ref") {
			c.JSON(http.StatusConflict, gin.H{"error": "a bank settlement is already recorded for this booking"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record bank settlement: " + err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Bank settlement recorded", "id": id, "booking_ref": ref})
}

// ── Gateway fee settings ──────────────────────────────────

// GET /admin/gateway-settings
func adminGetGatewaySettings(c *gin.Context) {
	rows, err := db.Query(`SELECT gateway, fee_percent, tax_on_fee_percent, COALESCE(updated_by,''), updated_at FROM gateway_settings ORDER BY gateway`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch gateway settings"})
		return
	}
	defer rows.Close()

	type setting struct {
		Gateway         string  `json:"gateway"`
		FeePercent      float64 `json:"fee_percent"`
		TaxOnFeePercent float64 `json:"tax_on_fee_percent"`
		UpdatedBy       string  `json:"updated_by,omitempty"`
		UpdatedAt       string  `json:"updated_at"`
	}
	out := []setting{}
	for rows.Next() {
		var s setting
		var updatedAt sql.NullTime
		if err := rows.Scan(&s.Gateway, &s.FeePercent, &s.TaxOnFeePercent, &s.UpdatedBy, &updatedAt); err == nil {
			if updatedAt.Valid {
				s.UpdatedAt = updatedAt.Time.Format("2006-01-02 15:04:05")
			}
			out = append(out, s)
		}
	}
	c.JSON(http.StatusOK, gin.H{"settings": out})
}

// PUT /admin/gateway-settings/:gateway
func adminSetGatewaySettings(c *gin.Context) {
	gateway := strings.ToLower(strings.TrimSpace(c.Param("gateway")))

	var body struct {
		FeePercent      float64 `json:"fee_percent"`
		TaxOnFeePercent float64 `json:"tax_on_fee_percent"`
		UpdatedBy       string  `json:"updated_by"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if body.FeePercent < 0 || body.TaxOnFeePercent < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "percentages cannot be negative"})
		return
	}

	res, err := db.Exec(`
		UPDATE gateway_settings
		SET fee_percent = $2, tax_on_fee_percent = $3, updated_by = NULLIF($4,''), updated_at = NOW()
		WHERE gateway = $1
	`, gateway, body.FeePercent, body.TaxOnFeePercent, body.UpdatedBy)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update gateway settings"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "unknown gateway"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Gateway settings updated", "gateway": gateway})
}

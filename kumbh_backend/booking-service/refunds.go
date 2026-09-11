package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// refundPolicy is loaded once at startup from the environment.
var refundPolicy RefundPolicy

// unsettledRefundStatuses are the states in which money is
// still owed to a customer, or a decision is still outstanding.
// A booking with a refund in any of these states must never be
// hard-deleted, or we lose the record of a debt we have not yet
// paid — or a request nobody has answered.
//
// 'rejected' is NOT here: it is a terminal decision, nothing is
// owed, so the booking may be cleaned up normally.
const unsettledRefundStatuses = `('awaiting_approval','pending','processing','failed','manual')`

// ── Model ────────────────────────────────────────────────

type Refund struct {
	ID                 int        `json:"id"`
	BookingRef         string     `json:"booking_ref"`
	Phone              string     `json:"phone"`
	TentName           string     `json:"tent_name,omitempty"`
	RazorpayPaymentID  string     `json:"razorpay_payment_id,omitempty"`
	RazorpayRefundID   string     `json:"razorpay_refund_id,omitempty"`
	BookingAmountPaise int64      `json:"booking_amount_paise"`
	RefundAmountPaise  int64      `json:"refund_amount_paise"`
	FeePaise           int64      `json:"fee_paise"`
	RefundAmount       float64    `json:"refund_amount"`
	PolicyRule         string     `json:"policy_rule,omitempty"`
	PolicyPercent      float64    `json:"policy_percent"`
	Currency           string     `json:"currency"`
	Status             string     `json:"status"`
	Attempts           int        `json:"attempts"`
	LastError          string     `json:"last_error,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	SettledAt          *time.Time `json:"settled_at,omitempty"`

	// Approval gate.
	RequestedAt     *time.Time `json:"requested_at,omitempty"`
	ReviewedBy      string     `json:"reviewed_by,omitempty"`
	ReviewedAt      *time.Time `json:"reviewed_at,omitempty"`
	RejectionReason string     `json:"rejection_reason,omitempty"`
	ApprovalReason  string     `json:"approval_reason,omitempty"`

	// Message is the customer-facing explanation.
	Message string `json:"message,omitempty"`
}

// customerMessage renders what the user should be told.
func (r *Refund) customerMessage() string {
	switch r.Status {
	case "awaiting_approval":
		return fmt.Sprintf(
			"Your refund request for ₹%.2f has been received and is awaiting approval by our team.",
			r.RefundAmount,
		)
	case "rejected":
		// The reason is staff-authored, so it is shown as given
		// rather than paraphrased.
		if r.RejectionReason != "" {
			return fmt.Sprintf("Your refund request was declined. Reason: %s", r.RejectionReason)
		}
		return "Your refund request was declined. Please contact support."
	case "succeeded":
		return fmt.Sprintf("₹%.2f has been refunded to your original payment method.", r.RefundAmount)
	case "pending", "processing", "failed":
		// "failed" is deliberately not surfaced as a failure:
		// it is retried automatically, so to the customer it
		// is still in progress. Staff see the real state.
		return fmt.Sprintf(
			"₹%.2f will be credited to your original payment method within %s working days.",
			r.RefundAmount, refundPolicy.SettlementDays,
		)
	case "manual":
		return fmt.Sprintf(
			"₹%.2f will be refunded by our team within %s working days.",
			r.RefundAmount, refundPolicy.SettlementDays,
		)
	default:
		return "No refund is due for this booking."
	}
}

const refundColumns = `
	id, booking_ref, phone, COALESCE(tent_name,''),
	COALESCE(razorpay_payment_id,''), COALESCE(razorpay_refund_id,''),
	booking_amount_paise, refund_amount_paise, fee_paise,
	COALESCE(policy_rule,''), COALESCE(policy_percent,0),
	currency, status, attempts, COALESCE(last_error,''),
	created_at, updated_at, settled_at,
	requested_at, COALESCE(reviewed_by,''), reviewed_at,
	COALESCE(rejection_reason,''), COALESCE(approval_reason,'')`

func scanRefund(s interface{ Scan(...any) error }) (*Refund, error) {
	var r Refund
	err := s.Scan(
		&r.ID, &r.BookingRef, &r.Phone, &r.TentName,
		&r.RazorpayPaymentID, &r.RazorpayRefundID,
		&r.BookingAmountPaise, &r.RefundAmountPaise, &r.FeePaise,
		&r.PolicyRule, &r.PolicyPercent,
		&r.Currency, &r.Status, &r.Attempts, &r.LastError,
		&r.CreatedAt, &r.UpdatedAt, &r.SettledAt,
		&r.RequestedAt, &r.ReviewedBy, &r.ReviewedAt, &r.RejectionReason,
		&r.ApprovalReason,
	)
	if err != nil {
		return nil, err
	}
	r.RefundAmount = float64(r.RefundAmountPaise) / 100.0
	r.Message = r.customerMessage()
	return &r, nil
}

// ── Razorpay gateway call ────────────────────────────────

// razorpayRefund issues a refund against a captured payment.
//
// MUST be called outside any database transaction: it is a
// network call to a third party with a multi-second timeout,
// and holding a row lock across it would stall every other
// cancellation for that booking.
func razorpayRefund(paymentID string, amountPaise int64, idempotencyKey string, notes map[string]string) (string, error) {
	keyID := os.Getenv("RAZORPAY_KEY_ID")
	keySecret := os.Getenv("RAZORPAY_KEY_SECRET")
	if keyID == "" || keySecret == "" {
		return "", fmt.Errorf("razorpay credentials not configured")
	}

	payload := map[string]interface{}{
		"amount": amountPaise,
		"speed":  envStr("RAZORPAY_REFUND_SPEED", "normal"),
		"notes":  notes,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("encode refund payload: %w", err)
	}

	url := fmt.Sprintf("https://api.razorpay.com/v1/payments/%s/refund", paymentID)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return "", fmt.Errorf("build refund request: %w", err)
	}
	req.SetBasicAuth(keyID, keySecret)
	req.Header.Set("Content-Type", "application/json")
	// Razorpay honours this on the refund endpoint; if a given
	// account/plan ignores it, the DB unique index on
	// booking_ref plus the status claim below remain the real
	// guarantee against a double refund.
	req.Header.Set("X-Razorpay-Idempotency-Key", idempotencyKey)

	timeout := time.Duration(envFloat("REFUND_GATEWAY_TIMEOUT_SECONDS", 20)) * time.Second
	client := &http.Client{Timeout: timeout}

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("reach razorpay: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("razorpay refund failed (HTTP %d): %s",
			resp.StatusCode, truncate(string(respBody), 400))
	}

	var out struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", fmt.Errorf("decode razorpay response: %w", err)
	}
	if out.ID == "" {
		return "", fmt.Errorf("razorpay response missing refund id: %s", truncate(string(respBody), 200))
	}
	return out.ID, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// refundApprovalReason returns the justification captured when the
// refund was approved. Threaded into ledger narrations so the
// accounting trail carries WHY money left, not just that it did —
// an auditor reading the ledger should not have to cross-reference
// the refunds table to answer that.
func refundApprovalReason(bookingRef string) string {
	var reason sql.NullString
	db.QueryRow(`SELECT approval_reason FROM refunds WHERE booking_ref = $1`, bookingRef).Scan(&reason)
	if reason.Valid && strings.TrimSpace(reason.String) != "" {
		return " — " + strings.TrimSpace(reason.String)
	}
	return ""
}

// ── Execution ────────────────────────────────────────────

// executeRefund claims a refund row and calls the gateway.
//
// The claim is a conditional UPDATE: only one caller can move
// a row out of pending/failed, so concurrent cancels, retries
// and the background worker cannot double-send. If the claim
// affects zero rows, someone else owns it and we return.
func executeRefund(refundID int) {
	var (
		bookingRef, paymentID, idemKey string
		amountPaise                    int64
		attempts                       int
	)

	err := db.QueryRow(`
		UPDATE refunds
		SET status = 'processing', attempts = attempts + 1, updated_at = NOW()
		WHERE id = $1
		  AND status IN ('pending', 'failed')
		  AND attempts < $2
		RETURNING booking_ref, COALESCE(razorpay_payment_id,''),
		          idempotency_key, refund_amount_paise, attempts
	`, refundID, refundPolicy.MaxAttempts).
		Scan(&bookingRef, &paymentID, &idemKey, &amountPaise, &attempts)

	if err == sql.ErrNoRows {
		// Already claimed, already settled, or out of attempts.
		return
	}
	if err != nil {
		fmt.Printf("⚠️  refund %d: could not claim: %v\n", refundID, err)
		return
	}

	if paymentID == "" || paymentID == "CASH" {
		// Nothing to call a gateway with — staff must settle.
		markRefundManual(refundID, "no gateway payment id; requires manual settlement")
		return
	}

	fmt.Printf("💸 refund %d: sending ₹%.2f for %s (attempt %d)\n",
		refundID, float64(amountPaise)/100, bookingRef, attempts)

	gatewayRefundID, err := razorpayRefund(paymentID, amountPaise, idemKey, map[string]string{
		"booking_ref": bookingRef,
		"reason":      "booking_cancelled",
	})

	if err != nil {
		// Leave a retryable record: status back to 'failed'
		// with the error preserved. The worker will pick it
		// up again, and staff can force a retry.
		_, uerr := db.Exec(`
			UPDATE refunds
			SET status = 'failed', last_error = $2, updated_at = NOW()
			WHERE id = $1
		`, refundID, err.Error())
		if uerr != nil {
			fmt.Printf("⚠️  refund %d: could not record failure: %v\n", refundID, uerr)
		}
		fmt.Printf("❌ refund %d for %s failed (attempt %d/%d): %v\n",
			refundID, bookingRef, attempts, refundPolicy.MaxAttempts, err)
		return
	}

	_, err = db.Exec(`
		UPDATE refunds
		SET status = 'succeeded', razorpay_refund_id = $2,
		    last_error = NULL, settled_at = NOW(), updated_at = NOW()
		WHERE id = $1
	`, refundID, gatewayRefundID)
	if err != nil {
		// The money HAS moved. Log loudly — this row now
		// understates reality and needs manual reconciliation.
		fmt.Printf("🚨 refund %d SENT to gateway (%s) but DB update failed: %v\n",
			refundID, gatewayRefundID, err)
		return
	}

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, refund_amount_paise, triggered_by, note)
		VALUES ($1, 'REFUND_SETTLED', $2, 'system:razorpay-gateway', $3)
	`, bookingRef, amountPaise, "razorpay_refund_id="+gatewayRefundID)

	// Auto-reverse ledger entry: the original booking payment was
	// Bank/Gateway Dr, Customer/Revenue Cr — a gateway refund
	// mirrors that exactly, Customer/Revenue Dr, Bank/Gateway Cr.
	go postLedgerPair(
		time.Now().Format("2006-01-02"), "refund", bookingRef,
		"Customer/Revenue", "Bank/Gateway", float64(amountPaise)/100.0,
		"Razorpay refund "+gatewayRefundID+refundApprovalReason(bookingRef),
	)

	fmt.Printf("✅ refund %d settled for %s → %s\n", refundID, bookingRef, gatewayRefundID)
	notifyRefund(bookingRef)
}

func markRefundManual(refundID int, reason string) {
	_, err := db.Exec(`
		UPDATE refunds
		SET status = 'manual', last_error = $2, updated_at = NOW()
		WHERE id = $1
	`, refundID, reason)
	if err != nil {
		fmt.Printf("⚠️  refund %d: could not mark manual: %v\n", refundID, err)
		return
	}
	fmt.Printf("📋 refund %d flagged for manual settlement: %s\n", refundID, reason)
}

// notifyRefund pushes an FCM message once money is on its way.
func notifyRefund(bookingRef string) {
	var fcmToken, tentName string
	var amount float64

	err := db.QueryRow(`
		SELECT COALESCE(u.fcm_token,''), COALESCE(r.tent_name,''),
		       r.refund_amount_paise / 100.0
		FROM refunds r
		JOIN users u ON u.phone = r.phone
		WHERE r.booking_ref = $1
	`, bookingRef).Scan(&fcmToken, &tentName, &amount)

	if err != nil || fcmToken == "" {
		return
	}

	go sendFCMNotification(
		fcmToken,
		"💰 Refund Processed",
		fmt.Sprintf("₹%.2f for %s (Ref: %s) is on its way to your original payment method.",
			amount, tentName, bookingRef),
	)
}

// ── Background retry worker ──────────────────────────────

// startRefundRetryWorker re-drives refunds the gateway
// rejected. Runs alongside the existing reminder scheduler.
func startRefundRetryWorker() {
	interval := time.Duration(envFloat("REFUND_RETRY_INTERVAL_MINUTES", 15)) * time.Minute
	if interval < time.Minute {
		interval = time.Minute
	}

	fmt.Printf("🔁 Refund retry worker every %s (max %d attempts)\n",
		interval, refundPolicy.MaxAttempts)

	// Small delay so the service finishes booting first.
	time.Sleep(30 * time.Second)

	for {
		runIfLeader("refund_retry_worker", retryPendingRefunds)
		time.Sleep(interval)
	}
}

func retryPendingRefunds() {
	rows, err := db.Query(`
		SELECT id FROM refunds
		WHERE status IN ('pending', 'failed')
		  AND attempts < $1
		ORDER BY created_at ASC
		LIMIT 50
	`, refundPolicy.MaxAttempts)
	if err != nil {
		fmt.Printf("⚠️  refund retry sweep failed: %v\n", err)
		return
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err == nil {
			ids = append(ids, id)
		}
	}

	if len(ids) == 0 {
		return
	}
	fmt.Printf("🔁 retrying %d unsettled refund(s)\n", len(ids))
	for _, id := range ids {
		executeRefund(id)
	}
}

// ── HTTP handlers ────────────────────────────────────────

// getBookingRefund returns the refund for one of the caller's
// own bookings.  GET /bookings/:ref/refund
func getBookingRefund(c *gin.Context) {
	phone := verifiedPhone(c)
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ref := c.Param("ref")

	row := db.QueryRow(`SELECT `+refundColumns+`
		FROM refunds WHERE booking_ref = $1 AND phone = $2`, ref, phone)

	r, err := scanRefund(row)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "no refund for this booking"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch refund"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"refund": r})
}

// getRefundQuote previews what cancelling would return, so the
// UI can state the amount BEFORE the user confirms.
// GET /bookings/:ref/refund-quote
func getRefundQuote(c *gin.Context) {
	phone := verifiedPhone(c)
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ref := c.Param("ref")

	var (
		totalAmount    float64
		status         string
		nights, tentID int
		checkIn        time.Time
		paymentID      sql.NullString
	)
	err := db.QueryRow(`
		SELECT total_amount, status, nights, tent_id, check_in, payment_id
		FROM bookings WHERE booking_ref = $1 AND phone = $2
	`, ref, phone).Scan(&totalAmount, &status, &nights, &tentID, &checkIn, &paymentID)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch booking"})
		return
	}

	policy, perr := loadCancellationPolicy(db, tentID)
	if perr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load cancellation policy"})
		return
	}

	paidPaise := paidAmountPaise(ref, status, totalAmount, paymentID)

	var alreadyRefunded bool
	_ = db.QueryRow(`SELECT EXISTS(SELECT 1 FROM refunds WHERE booking_ref = $1)`, ref).Scan(&alreadyRefunded)

	result := calculateRefund(BookingForRefund{
		BookingRef:      ref,
		PaidPaise:       paidPaise,
		NightPaise:      nightPaiseFor(paidPaise, nights),
		CheckIn:         checkIn,
		Status:          status,
		AlreadyRefunded: alreadyRefunded,
		Policy:          policy,
	}, nowIST())

	quote := RefundQuote{
		RefundPaise: result.RefundAmountPaise,
		Percent:     result.RefundPercent,
		Rule:        result.TierApplied,
	}

	c.JSON(http.StatusOK, gin.H{
		"booking_ref":                ref,
		"cancellable":                status != "cancelled" && status != "completed" && status != "no_show",
		"booking_status":             status,
		"refund_amount":              float64(result.RefundAmountPaise) / 100.0,
		"tier_applied":               result.TierApplied,
		"policy_percent":             result.RefundPercent,
		"policy_rule":                result.Rule,
		"penalty_amount":             float64(result.PenaltyAmountPaise) / 100.0,
		"free_cancellation_deadline": checkIn.Add(-time.Duration(policy.FreeCancellationHours) * time.Hour),
		"late_cancellation_cutoff":   checkIn.Add(-time.Duration(policy.LateCancellationHours) * time.Hour),
		"no_show_cutoff_time":        checkIn.Add(time.Duration(policy.NoShowCutoffHours) * time.Hour),
		"settlement_days":            refundPolicy.SettlementDays,
		"message":                    quoteMessage(quote),
	})
}

func quoteMessage(q RefundQuote) string {
	if q.RefundPaise <= 0 {
		return "No refund is due if you cancel this booking."
	}
	if refundPolicy.RequireApproval {
		// Do not promise the money outright — a human still has
		// to approve it.
		return fmt.Sprintf(
			"A refund of ₹%.2f will be requested for approval. Once approved, "+
				"it is credited to your original payment method within %s working days.",
			q.RefundRupees(), refundPolicy.SettlementDays,
		)
	}
	return fmt.Sprintf(
		"You will receive ₹%.2f back in your original payment method within %s working days.",
		q.RefundRupees(), refundPolicy.SettlementDays,
	)
}

// adminListRefunds powers the staff console.
// GET /admin/refunds?status=failed
func adminListRefunds(c *gin.Context) {
	status := c.Query("status")

	limit := 200
	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 1000 {
			limit = n
		}
	}

	var (
		rows *sql.Rows
		err  error
	)
	if status != "" {
		rows, err = db.Query(`SELECT `+refundColumns+`
			FROM refunds WHERE status = $1
			ORDER BY created_at DESC LIMIT $2`, status, limit)
	} else {
		rows, err = db.Query(`SELECT `+refundColumns+`
			FROM refunds ORDER BY created_at DESC LIMIT $1`, limit)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch refunds"})
		return
	}
	defer rows.Close()

	refunds := []*Refund{}
	var owedPaise, awaitingPaise int64
	awaiting := 0
	for rows.Next() {
		r, err := scanRefund(rows)
		if err != nil {
			continue
		}
		switch r.Status {
		case "succeeded", "not_applicable", "rejected":
			// Already paid, or nothing was ever owed. A
			// rejected refund is a closed decision, so it must
			// not inflate the outstanding-liability figure.
		case "awaiting_approval":
			owedPaise += r.RefundAmountPaise
			awaitingPaise += r.RefundAmountPaise
			awaiting++
		default:
			owedPaise += r.RefundAmountPaise
		}
		refunds = append(refunds, r)
	}

	c.JSON(http.StatusOK, gin.H{
		"refunds":           refunds,
		"total":             len(refunds),
		"outstanding":       float64(owedPaise) / 100.0,
		"awaiting_approval": awaiting,
		"awaiting_amount":   float64(awaitingPaise) / 100.0,
		"requires_approval": refundPolicy.RequireApproval,
		"active_policy":     refundPolicy.Describe(),
		"max_attempts":      refundPolicy.MaxAttempts,
	})
}

// ── Approval gate ────────────────────────────────────────

// reviewerFrom identifies the acting admin for the audit trail.
// The gateway does not yet forward admin identity, so the
// caller supplies it and we fall back to a marker rather than
// recording a false name.
func reviewerFrom(c *gin.Context, bodyReviewer string) string {
	if v := strings.TrimSpace(bodyReviewer); v != "" {
		return v
	}
	if v := strings.TrimSpace(c.GetHeader("X-Admin-Username")); v != "" {
		return v
	}
	return "unknown-admin"
}

// adminApproveRefund releases a refund to the payment gateway.
// POST /admin/refunds/:ref/approve
//
// The status transition is a conditional UPDATE, so two admins
// clicking Approve at the same moment cannot both dispatch:
// the second sees zero rows affected.
func adminApproveRefund(c *gin.Context) {
	ref := c.Param("ref")

	var body struct {
		Reason   string `json:"reason"`
		Reviewer string `json:"reviewer"`
	}
	_ = c.ShouldBindJSON(&body)

	// Approving is the decision that actually moves money out, so it
	// carries the same "must be explainable later" bar that rejecting
	// already did. Enforced in the DB too — see migration 013.
	reason := strings.TrimSpace(body.Reason)
	if reason == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason is required to approve a refund"})
		return
	}
	reviewer := reviewerFrom(c, body.Reviewer)

	var (
		refundID  int
		paymentID sql.NullString
		amount    int64
	)
	err := db.QueryRow(`
		UPDATE refunds
		SET status = CASE
		        -- Cash bookings have no gateway payment to
		        -- reverse; approving them hands the task to
		        -- staff rather than to Razorpay.
		        WHEN razorpay_payment_id IS NULL
		          OR razorpay_payment_id = ''
		          OR razorpay_payment_id = 'CASH' THEN 'manual'
		        ELSE 'pending'
		    END,
		    approval_reason = $3,
		    reviewed_by = $2, reviewed_at = NOW(), updated_at = NOW()
		WHERE booking_ref = $1
		  AND status = 'awaiting_approval'
		RETURNING id, razorpay_payment_id, refund_amount_paise
	`, ref, reviewer, reason).Scan(&refundID, &paymentID, &amount)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusConflict, gin.H{
			"error": "no refund awaiting approval for this booking (already decided, or none exists)",
		})
		return
	}
	if err != nil {
		fmt.Printf("⚠️  approve %s failed: %v\n", ref, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to approve refund"})
		return
	}

	gatewayBound := paymentID.Valid && paymentID.String != "" && paymentID.String != "CASH"
	if gatewayBound {
		// Outside any transaction, as always.
		go executeRefund(refundID)
	}

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, refund_amount_paise, triggered_by, note)
		VALUES ($1, 'REFUND_APPROVED', $2, $3, $4)
	`, ref, amount, "admin:"+reviewer, reason)

	fmt.Printf("refund for %s approved by %s (₹%.2f) — %s\n", ref, reviewer, float64(amount)/100, reason)

	c.JSON(http.StatusOK, gin.H{
		"message":         "Refund approved",
		"booking_ref":     ref,
		"refund_id":       refundID,
		"refund_amount":   float64(amount) / 100,
		"status":          map[bool]string{true: "pending", false: "manual"}[gatewayBound],
		"reviewed_by":     reviewer,
		"approval_reason": reason,
	})
}

// adminRejectRefund declines a refund. Terminal — nothing is
// ever sent to the gateway.
// POST /admin/refunds/:ref/reject
func adminRejectRefund(c *gin.Context) {
	ref := c.Param("ref")

	var body struct {
		Reason   string `json:"reason"`
		Reviewer string `json:"reviewer"`
	}
	_ = c.ShouldBindJSON(&body)

	// A refusal to return someone's money has to be explainable
	// later; the DB enforces this too (ck_refunds_rejected_has_reason).
	reason := strings.TrimSpace(body.Reason)
	if reason == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason is required to reject a refund"})
		return
	}
	reviewer := reviewerFrom(c, body.Reviewer)

	var refundID int
	err := db.QueryRow(`
		UPDATE refunds
		SET status = 'rejected', rejection_reason = $2,
		    reviewed_by = $3, reviewed_at = NOW(), updated_at = NOW()
		WHERE booking_ref = $1
		  AND status = 'awaiting_approval'
		RETURNING id
	`, ref, reason, reviewer).Scan(&refundID)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusConflict, gin.H{
			"error": "no refund awaiting approval for this booking (already decided, or none exists)",
		})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reject refund"})
		return
	}

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, triggered_by, note)
		VALUES ($1, 'REFUND_REJECTED', $2, $3)
	`, ref, "admin:"+reviewer, reason)

	fmt.Printf("🚫 refund for %s rejected by %s: %s\n", ref, reviewer, reason)
	notifyRefundRejected(ref, reason)

	c.JSON(http.StatusOK, gin.H{
		"message":     "Refund rejected",
		"booking_ref": ref,
		"refund_id":   refundID,
		"reason":      reason,
		"reviewed_by": reviewer,
	})
}

// notifyRefundRejected tells the customer a decision was made.
func notifyRefundRejected(bookingRef, reason string) {
	var fcmToken, tentName string
	err := db.QueryRow(`
		SELECT COALESCE(u.fcm_token,''), COALESCE(r.tent_name,'')
		FROM refunds r
		JOIN users u ON u.phone = r.phone
		WHERE r.booking_ref = $1
	`, bookingRef).Scan(&fcmToken, &tentName)

	if err != nil || fcmToken == "" {
		return
	}
	go sendFCMNotification(
		fcmToken,
		"Refund Request Update",
		fmt.Sprintf("Your refund request for %s (Ref: %s) was not approved. Reason: %s",
			tentName, bookingRef, reason),
	)
}

// adminRetryRefund lets staff force a retry, including for
// refunds that exhausted their automatic attempts.
// POST /admin/refunds/:ref/retry
func adminRetryRefund(c *gin.Context) {
	ref := c.Param("ref")

	// Reset to 'pending' and clear the attempt budget so the
	// claim in executeRefund can take it. Only rows that are
	// genuinely unsettled are eligible — a succeeded refund
	// can never be re-sent from here.
	var id int
	err := db.QueryRow(`
		UPDATE refunds
		SET status = 'pending', attempts = 0, last_error = NULL, updated_at = NOW()
		WHERE booking_ref = $1
		  AND status IN ('failed', 'manual', 'pending')
		RETURNING id
	`, ref).Scan(&id)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusConflict, gin.H{
			"error": "no retryable refund for this booking (already settled, or none exists)",
		})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to queue retry"})
		return
	}

	go executeRefund(id)

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, triggered_by)
		VALUES ($1, 'REFUND_RETRY_QUEUED', $2)
	`, ref, "admin:"+reviewerFrom(c, ""))

	c.JSON(http.StatusAccepted, gin.H{
		"message":     "Refund retry queued",
		"booking_ref": ref,
		"refund_id":   id,
	})
}

// adminMarkRefundSettled records an out-of-band settlement
// (cash handed back, manual NEFT) so the ledger closes.
// POST /admin/refunds/:ref/settle
func adminMarkRefundSettled(c *gin.Context) {
	ref := c.Param("ref")

	var body struct {
		Reference string `json:"reference"`
		Note      string `json:"note"`
		Reviewer  string `json:"reviewer"`
	}
	_ = c.ShouldBindJSON(&body)

	if body.Reference == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "reference is required (bank UTR, cash receipt no, etc.)",
		})
		return
	}
	reviewer := reviewerFrom(c, body.Reviewer)

	// razorpay_refund_id carries the external reference so the
	// ck_refunds_succeeded_has_gateway_id constraint holds.
	var refundAmountPaise int64
	err := db.QueryRow(`
		UPDATE refunds
		SET status = 'succeeded', razorpay_refund_id = $2,
		    last_error = $3, settled_at = NOW(), updated_at = NOW()
		WHERE booking_ref = $1
		  AND status IN ('manual', 'failed', 'pending')
		RETURNING refund_amount_paise
	`, ref, "manual:"+body.Reference, nullableNote(body.Note)).Scan(&refundAmountPaise)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusConflict, gin.H{
			"error": "no unsettled refund for this booking",
		})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to settle refund"})
		return
	}

	db.Exec(`
		INSERT INTO refund_audit_log (booking_ref, event, triggered_by, note)
		VALUES ($1, 'REFUND_SETTLED', $2, $3)
	`, ref, "admin:"+reviewer, "reference="+body.Reference)

	// Auto-reverse ledger entry. This settlement is manual (cash
	// handed back, or a bank refund outside the gateway), so the
	// account it reverses depends on how the ORIGINAL payment was
	// taken, not always "Bank/Gateway" the way the automatic
	// gateway-refund path in executeRefund can assume.
	var originalMode string
	db.QueryRow(`
		SELECT COALESCE(payment_mode, 'razorpay') FROM payments
		WHERE booking_ref = $1 AND status = 'success' ORDER BY created_at DESC LIMIT 1
	`, ref).Scan(&originalMode)
	if originalMode == "" {
		originalMode = "razorpay"
	}
	go postLedgerPair(
		time.Now().Format("2006-01-02"), "refund", ref,
		"Customer/Revenue", bankAccountFor(originalMode), float64(refundAmountPaise)/100.0,
		"Manual refund settlement: "+body.Reference+refundApprovalReason(ref),
	)

	notifyRefund(ref)
	c.JSON(http.StatusOK, gin.H{
		"message":     "Refund marked settled",
		"booking_ref": ref,
		"reference":   body.Reference,
	})
}

func nullableNote(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

// ── Booking amount helper ────────────────────────────────

// paidAmountPaise returns how much was actually collected for
// a booking, in paise.
//
// Source of truth is the payments table (a successful gateway
// capture), not bookings.total_amount, so an unpaid or
// partially-paid booking cannot trigger a refund of money the
// business never received.
func paidAmountPaise(bookingRef, bookingStatus string, totalAmount float64, paymentID sql.NullString) int64 {
	var paid sql.NullFloat64
	err := db.QueryRow(`
		SELECT SUM(amount) FROM payments
		WHERE booking_ref = $1 AND status = 'success'
	`, bookingRef).Scan(&paid)

	if err == nil && paid.Valid && paid.Float64 > 0 {
		return int64(paid.Float64*100 + 0.5)
	}

	// Cash bookings never produce a payments row, but a
	// confirmed cash booking has been paid at the tent.
	if paymentID.Valid && paymentID.String == "CASH" && bookingStatus == "confirmed" {
		return int64(totalAmount*100 + 0.5)
	}

	return 0
}

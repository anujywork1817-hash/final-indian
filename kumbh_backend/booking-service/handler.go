package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type Booking struct {
	ID          int       `json:"id"`
	BookingRef  string    `json:"booking_ref"`
	Phone       string    `json:"phone"`
	TentID      int       `json:"tent_id"`
	TentName    string    `json:"tent_name"`
	Location    string    `json:"location"`
	Class       string    `json:"class"`
	CheckIn     string    `json:"check_in"`
	CheckOut    string    `json:"check_out"`
	Nights      int       `json:"nights"`
	Guests      int       `json:"guests"`
	Units       int       `json:"units"`
	BaseAmount  float64   `json:"base_amount"`
	CouponCode  string    `json:"coupon_code,omitempty"`
	Discount    float64   `json:"discount"`
	Tax         float64   `json:"tax"`
	TotalAmount float64   `json:"total_amount"`
	Status      string    `json:"status"`
	PaymentID   string    `json:"payment_id,omitempty"`
	GuestName   string    `json:"guest_name,omitempty"`
	GuestPhone  string    `json:"guest_phone,omitempty"`
	IDProof     string    `json:"id_proof,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	Images      []string  `json:"images"`

	// Refund fields, populated for cancelled bookings so the
	// app can show the real state instead of a hardcoded
	// "processing" badge.
	RefundStatus  string  `json:"refund_status,omitempty"`
	RefundAmount  float64 `json:"refund_amount"`
	RefundMessage string  `json:"refund_message,omitempty"`
}

func createBooking(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		TentID     int                    `json:"tent_id" binding:"required"`
		CheckIn    string                 `json:"check_in" binding:"required"`
		CheckOut   string                 `json:"check_out" binding:"required"`
		Guests     int                    `json:"guests"`
		Units      int                    `json:"units"`
		CouponCode string                 `json:"coupon_code"`
		Addons     map[string]interface{} `json:"addons"`
		// Optional — the app has no currency picker yet, so this
		// is almost always absent and every booking stays INR.
		Currency string `json:"currency"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Guests == 0 {
		req.Guests = 1
	}
	if req.Units == 0 {
		req.Units = 1
	}

	// ── BUG-12: validate dates up front ──────────────────────
	// time.Parse errors were previously discarded (`checkIn, _ :=`),
	// so a malformed date silently produced a zero time and a booking
	// for year 1. Also reject stays that start in the past.
	checkIn, errIn := time.Parse("2006-01-02", req.CheckIn)
	checkOut, errOut := time.Parse("2006-01-02", req.CheckOut)
	if errIn != nil || errOut != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "check_in and check_out must be YYYY-MM-DD dates"})
		return
	}
	today := time.Now().UTC().Truncate(24 * time.Hour)
	if checkIn.Before(today) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "check-in date is in the past"})
		return
	}
	if !checkOut.After(checkIn) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "check-out must be after check-in"})
		return
	}

	guestName := ""
	guestPhone := ""
	idProof := ""
	bedType := "Single"
	genderPref := "Mixed"

	if req.Addons != nil {
		if v, ok := req.Addons["guest_name"].(string); ok {
			guestName = v
		}
		if v, ok := req.Addons["guest_phone"].(string); ok {
			guestPhone = v
		}
		if v, ok := req.Addons["id_proof"].(string); ok {
			idProof = v
		}
		if v, ok := req.Addons["bed_type"].(string); ok {
			bedType = v
		}
		if v, ok := req.Addons["gender_preference"].(string); ok {
			genderPref = v
		}
	}

	addonsJSON, _ := json.Marshal(req.Addons)

	// ── BEGIN TRANSACTION with lock ───────────────────────────
	tx, err := db.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback()

	// ── Step 1: Lock tent row + get total_units ───────────────
	// FOR UPDATE locks this row — other requests wait here
	var tentName, location, class string
	var pricePerNight, totalUnits int
	err = tx.QueryRow(`
		SELECT name, price, location, class, total_units
		FROM tents
		WHERE id = $1 AND is_active = TRUE
		FOR UPDATE
	`, req.TentID).Scan(&tentName, &pricePerNight, &location, &class, &totalUnits)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "tent not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch tent"})
		}
		return
	}

	// ── Step 2: Per-day booked units for every date in range ──
	// Safe — no other request can slip in between (tents row is
	// locked FOR UPDATE above, and every booking-writing path locks
	// the same row first, so concurrent attempts for this tent are
	// fully serialized here even though this query itself has no
	// row lock of its own).
	_, days, err := dailyAvailability(tx, req.TentID, req.CheckIn, req.CheckOut)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "availability check failed"})
		return
	}

	// ── Step 3: Every date in the range must have enough units ─
	// A date-range booking is only valid if EVERY day in it clears
	// the bar — one bad day (e.g. a middle night already full)
	// must reject the whole range, not just the days that fail.
	var shortDates []string
	minRemaining := totalUnits
	for _, d := range days {
		remaining := totalUnits - d.BookedUnits
		if remaining < minRemaining {
			minRemaining = remaining
		}
		if remaining < req.Units {
			shortDates = append(shortDates, d.Date)
		}
	}
	if len(shortDates) > 0 {
		c.JSON(http.StatusConflict, gin.H{
			"error":           fmt.Sprintf("Not enough units available for: %s", strings.Join(shortDates, ", ")),
			"dates":           shortDates,
			"total_units":     totalUnits,
			"remaining_units": minRemaining,
		})
		return
	}

	// ── Step 4: Calculate amounts (server is the source of truth) ─
	nights := int(checkOut.Sub(checkIn).Hours() / 24)

	// BUG-08: the bed-type surcharge and child fee were previously
	// computed only in the Flutter UI and the client's total was
	// trusted. computeBookingCharges (pricing.go) runs the same
	// formula server-side so the amount charged can't be tampered
	// with client-side. BUG-03/04: the GST slab inside it is decided
	// by the per-unit-night tariff, not the aggregated stay total.
	childrenAbove5 := 0
	if req.Addons != nil {
		if v, ok := req.Addons["children_5_to_12"].(float64); ok {
			childrenAbove5 = int(v)
		}
	}

	// ── Step 5: Validate coupon (applies to the whole subtotal) ──
	// Price once with no discount to learn the subtotal the coupon's
	// min_amount is checked against, then re-price with the rate.
	discountRate := 0.0
	couponCode := ""
	if req.CouponCode != "" {
		preCoupon := computeBookingCharges(pricePerNight, nights, req.Units, childrenAbove5, bedType, 0)

		var rate float64
		var minAmount int
		var usedCount, maxUses int
		var isActive bool
		var expiresAt time.Time

		err := tx.QueryRow(`
			SELECT discount, min_amount, used_count, max_uses, is_active, expires_at
			FROM coupons WHERE code = $1
		`, req.CouponCode).Scan(&rate, &minAmount, &usedCount, &maxUses, &isActive, &expiresAt)

		if err == nil && isActive &&
			usedCount < maxUses &&
			time.Now().Before(expiresAt) &&
			preCoupon.Subtotal >= float64(minAmount) {
			discountRate = rate
			couponCode = req.CouponCode
			// BUG-07: do NOT bump used_count here — the booking is
			// still 'pending' and may never be paid. The increment
			// happens when payment is verified (payment-service).
		}
	}

	charges := computeBookingCharges(pricePerNight, nights, req.Units, childrenAbove5, bedType, discountRate)
	baseAmount := charges.Base
	discount := charges.Discount
	tax := charges.Tax
	totalAmount := charges.Total

	// ── Step 5b: Lock today's exchange rate, if foreign ───────
	//
	// HARD RULE (multi-currency Phase 3): this rate is captured
	// ONCE, here, at booking time, and never recalculated —
	// see currency.go. An INR booking (the only kind the app's
	// current UI produces) locks in currency="INR", rate=1,
	// foreign_amount=NULL, so nothing changes for it.
	lockedCurrency, lockedRate, foreignAmount := lockExchangeRateFor(req.Currency, totalAmount)

	// ── Step 6: Generate unique booking ref ───────────────────
	ref := fmt.Sprintf("KTB-2027-%05d", rand.Intn(99999))

	// ── Step 7: Insert booking ────────────────────────────────
	var bookingID int
	err = tx.QueryRow(`
		INSERT INTO bookings
			(booking_ref, phone, tent_id, tent_name, location, class,
			 check_in, check_out, nights, guests, units,
			 base_amount, coupon_code, discount, tax, total_amount, status,
			 guest_name, guest_phone, id_proof, bed_type, gender_preference, addons,
			 currency, exchange_rate, foreign_amount)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'pending',$17,$18,$19,$20,$21,$22,$23,$24,$25)
		RETURNING id
	`, ref, phone, req.TentID, tentName, location, class,
		req.CheckIn, req.CheckOut,
		nights, req.Guests, req.Units,
		baseAmount, couponCode, discount, tax, totalAmount,
		guestName, guestPhone, idProof, bedType, genderPref, string(addonsJSON),
		lockedCurrency, lockedRate, foreignAmount,
	).Scan(&bookingID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create booking: " + err.Error()})
		return
	}

	// ── Step 8: Commit — releases the lock ────────────────────
	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to confirm booking"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"booking": gin.H{
			"id":              bookingID,
			"booking_ref":     ref,
			"tent_name":       tentName,
			"location":        location,
			"class":           class,
			"check_in":        req.CheckIn,
			"check_out":       req.CheckOut,
			"nights":          nights,
			"guests":          req.Guests,
			"units":           req.Units,
			"base_amount":     baseAmount,
			"coupon_code":     couponCode,
			"discount":        discount,
			"tax":             tax,
			"total_amount":    totalAmount,
			"status":          "pending",
			"remaining_units": minRemaining - req.Units,
		},
		"message": "Booking created! Complete payment to confirm.",
	})
}

func myBookings(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	rows, err := db.Query(`
		SELECT b.id, b.booking_ref, b.phone, b.tent_id, b.tent_name,
		       COALESCE(b.location,''), COALESCE(b.class,''),
		       b.check_in, b.check_out, b.nights, b.guests, b.units,
		       b.base_amount, COALESCE(b.coupon_code,''), b.discount, b.tax,
		       b.total_amount, b.status, COALESCE(b.payment_id,''),
		       COALESCE(b.guest_name,''), COALESCE(b.guest_phone,''), COALESCE(b.id_proof,''),
		       b.created_at,
		       COALESCE(t.images::text, '[]'),
		       COALESCE(r.status, ''),
		       COALESCE(r.refund_amount_paise, 0)
		FROM bookings b
		LEFT JOIN tents t ON t.id = b.tent_id
		LEFT JOIN refunds r ON r.booking_ref = b.booking_ref
		WHERE b.phone = $1
		ORDER BY b.created_at DESC
	`, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	defer rows.Close()

	var bookings []Booking
	for rows.Next() {
		var b Booking
		var imagesStr string
		var refundStatus string
		var refundPaise int64
		rows.Scan(
			&b.ID, &b.BookingRef, &b.Phone, &b.TentID, &b.TentName,
			&b.Location, &b.Class,
			&b.CheckIn, &b.CheckOut, &b.Nights, &b.Guests, &b.Units,
			&b.BaseAmount, &b.CouponCode, &b.Discount, &b.Tax,
			&b.TotalAmount, &b.Status, &b.PaymentID,
			&b.GuestName, &b.GuestPhone, &b.IDProof,
			&b.CreatedAt, &imagesStr,
			&refundStatus, &refundPaise,
		)
		json.Unmarshal([]byte(imagesStr), &b.Images)
		if b.Images == nil {
			b.Images = []string{}
		}

		if refundStatus != "" {
			b.RefundStatus = refundStatus
			b.RefundAmount = float64(refundPaise) / 100.0
			b.RefundMessage = (&Refund{
				Status:       refundStatus,
				RefundAmount: b.RefundAmount,
			}).customerMessage()
		}

		bookings = append(bookings, b)
	}

	if bookings == nil {
		bookings = []Booking{}
	}

	c.JSON(http.StatusOK, gin.H{
		"bookings": bookings,
		"total":    len(bookings),
	})
}

// cancelBooking cancels a booking and records the refund owed.
//
// Shape of this handler matters:
//  1. all DB work happens in ONE transaction, with the booking
//     row locked FOR UPDATE, so two concurrent cancels cannot
//     both create a refund;
//  2. the refund row is INSERTed inside that transaction, and
//     a UNIQUE index on refunds.booking_ref makes a second
//     insert impossible even if the lock were somehow bypassed;
//  3. the Razorpay call happens AFTER commit, outside the
//     transaction — a slow gateway must never hold a row lock.
//
// If the gateway call fails, the refund row survives as
// 'failed' and is retried by the background worker, so money
// owed is never silently dropped.
func cancelBooking(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ref := c.Param("ref")

	tx, err := db.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback()

	// ── Lock the booking row ──────────────────────────────
	//
	// FOR UPDATE also serializes concurrent cancel requests for
	// the same booking (spamming the Cancel button): the second
	// request blocks here until the first commits, then sees
	// status='cancelled' and is rejected below — never a double
	// refund, even without relying solely on the refunds table's
	// unique index.
	var (
		status, tentName string
		totalAmount      float64
		nights, tentID   int
		checkIn          time.Time
		paymentID        sql.NullString
	)
	err = tx.QueryRow(`
		SELECT status, COALESCE(tent_name,''), total_amount, nights, tent_id, check_in, payment_id
		FROM bookings
		WHERE booking_ref = $1 AND phone = $2
		FOR UPDATE
	`, ref, phone).Scan(&status, &tentName, &totalAmount, &nights, &tentID, &checkIn, &paymentID)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch booking"})
		return
	}

	if status == "cancelled" || status == "no_show" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "booking already cancelled"})
		return
	}
	if status == "completed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "completed booking cannot be cancelled"})
		return
	}

	// ── Work out what is owed, via the tiered policy ──────
	paidPaise := paidAmountPaise(ref, status, totalAmount, paymentID)
	policy, perr := loadCancellationPolicy(tx, tentID)
	if perr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load cancellation policy"})
		return
	}
	result := calculateRefund(BookingForRefund{
		BookingRef: ref,
		PaidPaise:  paidPaise,
		NightPaise: nightPaiseFor(paidPaise, nights),
		CheckIn:    checkIn,
		Status:     status,
		Policy:     policy,
	}, nowIST())
	quote := RefundQuote{
		RefundPaise: result.RefundAmountPaise,
		FeePaise:    0,
		Percent:     result.RefundPercent,
		Rule:        result.TierApplied,
	}

	// ── Cancel ────────────────────────────────────────────
	if _, err = tx.Exec(`
		UPDATE bookings SET status = 'cancelled', cancelled_at = NOW(), updated_at = NOW()
		WHERE booking_ref = $1 AND phone = $2
	`, ref, phone); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to cancel booking"})
		return
	}

	// ── Record the refund ─────────────────────────────────
	//
	// When approval is required, the refund is parked at
	// 'awaiting_approval' and NOTHING is sent to the gateway.
	// A human moves it to 'pending' (approve) or 'rejected'
	// (decline) via the admin endpoints; only then does the
	// existing execute/retry machinery pick it up.
	refundStatus := "pending"
	if refundPolicy.RequireApproval {
		refundStatus = "awaiting_approval"
	}
	gatewayPayment := ""
	switch {
	case quote.RefundPaise <= 0:
		// Nothing owed — no decision to make, so no queue entry.
		refundStatus = "not_applicable"
	case !paymentID.Valid || paymentID.String == "" || paymentID.String == "CASH":
		// Paid in cash at the tent. Still needs approval first;
		// only after that does it become a manual settlement
		// task for staff.
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
		) VALUES ($1,$2,$3,$4,NULLIF($5,''),$6,$7,$8,$9,$10,$11,$12,NOW())
		ON CONFLICT (booking_ref) DO NOTHING
		RETURNING id
	`,
		ref, phone, tentName, checkIn,
		gatewayPayment,
		paidPaise, quote.RefundPaise, quote.FeePaise,
		quote.Rule, quote.Percent, refundStatus,
		fmt.Sprintf("refund_%s", ref),
	).Scan(&refundID)

	alreadyExisted := false
	if err == sql.ErrNoRows {
		// ON CONFLICT DO NOTHING fired: a refund for this
		// booking already exists. Not an error — it is the
		// double-execution guard doing its job.
		alreadyExisted = true
		if err = tx.QueryRow(
			`SELECT id, refund_amount_paise, status FROM refunds WHERE booking_ref = $1`, ref,
		).Scan(&refundID, &quote.RefundPaise, &refundStatus); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read existing refund"})
			return
		}
	} else if err != nil {
		fmt.Printf("⚠️  could not record refund for %s: %v\n", ref, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record refund"})
		return
	}

	if !alreadyExisted {
		if _, aerr := tx.Exec(`
			INSERT INTO refund_audit_log
				(booking_ref, event, tier_applied, refund_amount_paise, penalty_amount_paise, triggered_by)
			VALUES ($1,'CANCELLED',$2,$3,$4,$5)
		`, ref, result.TierApplied, result.RefundAmountPaise, result.PenaltyAmountPaise, "user:"+phone); aerr != nil {
			// Never block a cancellation on the audit trail — log
			// loudly and continue; the refund itself is already
			// durably recorded in the refunds table above.
			fmt.Printf("⚠️  could not write audit log for %s: %v\n", ref, aerr)
		}
	}

	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit cancellation"})
		return
	}

	// ── Gateway call: AFTER commit, no locks held ─────────
	//
	// Only 'pending' dispatches. 'awaiting_approval' waits for a
	// human — this is the whole point of the gate.
	if refundStatus == "pending" && !alreadyExisted {
		go executeRefund(refundID)
	}

	message := "Booking cancelled successfully"
	switch {
	case quote.RefundPaise <= 0:
		// leave the plain message
	case refundStatus == "awaiting_approval":
		message = fmt.Sprintf(
			"Booking cancelled. Your refund request for ₹%.2f has been sent to our team for approval. "+
				"Once approved, the amount is credited to your original payment method within %s working days.",
			float64(quote.RefundPaise)/100, refundPolicy.SettlementDays,
		)
	default:
		message = fmt.Sprintf(
			"Booking cancelled. ₹%.2f will be credited to your original payment method within %s working days.",
			float64(quote.RefundPaise)/100, refundPolicy.SettlementDays,
		)
	}

	// Cancellation confirmation push. The customer-facing `message`
	// already states the refund outcome, so it doubles as the body
	// rather than re-deriving the wording here and risking the two
	// disagreeing.
	go notifyUser(phone, NotifBookingCancelled, ref,
		"Booking cancelled",
		fmt.Sprintf("Your booking at %s (Ref: %s) is cancelled. %s", tentName, ref, message),
	)

	c.JSON(http.StatusOK, gin.H{
		"message":           message,
		"booking_ref":       ref,
		"status":            "cancelled",
		"refund_amount":     float64(quote.RefundPaise) / 100,
		"penalty_amount":    float64(result.PenaltyAmountPaise) / 100,
		"refund_status":     refundStatus,
		"requires_approval": refundStatus == "awaiting_approval",
		"tier_applied":      result.TierApplied,
		"policy_rule":       quote.Rule,
		"policy_percent":    quote.Percent,
		"settlement_days":   refundPolicy.SettlementDays,
	})
}

func validateCoupon(c *gin.Context) {
	var req struct {
		Code   string  `json:"code" binding:"required"`
		Amount float64 `json:"amount"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var discount float64
	var description string
	var minAmount int
	var usedCount, maxUses int
	var isActive bool
	var expiresAt time.Time

	err := db.QueryRow(`
		SELECT discount, description, min_amount, used_count, max_uses, is_active, expires_at
		FROM coupons WHERE code = $1
	`, req.Code).Scan(&discount, &description, &minAmount, &usedCount, &maxUses, &isActive, &expiresAt)

	if err != nil {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Invalid coupon code"})
		return
	}
	if !isActive {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Coupon is inactive"})
		return
	}
	if usedCount >= maxUses {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Coupon usage limit reached"})
		return
	}
	if time.Now().After(expiresAt) {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Coupon has expired"})
		return
	}
	if req.Amount > 0 && req.Amount < float64(minAmount) {
		c.JSON(http.StatusOK, gin.H{
			"valid":   false,
			"message": fmt.Sprintf("Minimum booking amount ₹%d required", minAmount),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"valid":       true,
		"discount":    discount,
		"description": description,
		"message":     fmt.Sprintf("%.0f%% discount applied! %s", discount*100, description),
	})
}

func listCoupons(c *gin.Context) {
	rows, err := db.Query(`
		SELECT code, description, discount, min_amount, max_uses, used_count, expires_at
		FROM coupons WHERE is_active = TRUE AND expires_at > NOW()
		ORDER BY discount DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch coupons"})
		return
	}
	defer rows.Close()

	type Coupon struct {
		Code        string    `json:"code"`
		Description string    `json:"description"`
		Discount    float64   `json:"discount"`
		MinAmount   int       `json:"min_amount"`
		MaxUses     int       `json:"max_uses"`
		UsedCount   int       `json:"used_count"`
		ExpiresAt   time.Time `json:"expires_at"`
	}

	var coupons []Coupon
	for rows.Next() {
		var cp Coupon
		rows.Scan(&cp.Code, &cp.Description, &cp.Discount,
			&cp.MinAmount, &cp.MaxUses, &cp.UsedCount, &cp.ExpiresAt)
		coupons = append(coupons, cp)
	}
	if coupons == nil {
		coupons = []Coupon{}
	}
	c.JSON(http.StatusOK, gin.H{"coupons": coupons})
}
func deleteBooking(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	ref := c.Param("ref")

	// Only allow deleting cancelled bookings
	var status string
	err := db.QueryRow(`
		SELECT status FROM bookings WHERE booking_ref = $1 AND phone = $2
	`, ref, phone).Scan(&status)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	if status != "cancelled" && status != "no_show" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "only cancelled or no-show bookings can be deleted"})
		return
	}

	// A booking whose refund has not settled must not be
	// removed — the user would lose all visibility of money
	// they are still owed, and staff would lose the context
	// needed to chase it.
	var unsettled string
	err = db.QueryRow(`
		SELECT status FROM refunds
		WHERE booking_ref = $1 AND status IN `+unsettledRefundStatuses,
		ref).Scan(&unsettled)

	if err == nil {
		c.JSON(http.StatusConflict, gin.H{
			"error":         "cannot remove a booking with a refund still in progress",
			"refund_status": unsettled,
		})
		return
	}
	if err != sql.ErrNoRows {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check refund status"})
		return
	}

	// Note: the refunds row (if any) is deliberately NOT
	// deleted. It is a financial record and outlives the
	// booking; it carries its own snapshot of the details.
	if _, err = db.Exec(`
		DELETE FROM payments WHERE booking_ref = $1
	`, ref); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete payment records"})
		return
	}

	_, err = db.Exec(`
		DELETE FROM bookings WHERE booking_ref = $1 AND phone = $2
	`, ref, phone)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete booking"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Booking deleted successfully",
		"booking_ref": ref,
	})
}

// ── Admin Routes ─────────────────────────────────────────────────

// GET /admin/bookings — all bookings
func adminGetBookings(c *gin.Context) {
	rows, err := db.Query(`
		SELECT b.id, b.booking_ref, b.phone, b.tent_id, b.tent_name,
		       COALESCE(b.location,''), COALESCE(b.class,''),
		       b.check_in, b.check_out, b.nights, b.guests, b.units,
		       b.base_amount, COALESCE(b.coupon_code,''), b.discount, b.tax,
		       b.total_amount, b.status, COALESCE(b.payment_id,''),
		       COALESCE(b.guest_name,''), COALESCE(b.guest_phone,''), COALESCE(b.id_proof,''),
		       b.created_at
		FROM bookings b
		ORDER BY b.created_at DESC
		LIMIT 100
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	defer rows.Close()

	var bookings []Booking
	for rows.Next() {
		var b Booking
		rows.Scan(
			&b.ID, &b.BookingRef, &b.Phone, &b.TentID, &b.TentName,
			&b.Location, &b.Class,
			&b.CheckIn, &b.CheckOut, &b.Nights, &b.Guests, &b.Units,
			&b.BaseAmount, &b.CouponCode, &b.Discount, &b.Tax,
			&b.TotalAmount, &b.Status, &b.PaymentID,
			&b.GuestName, &b.GuestPhone, &b.IDProof,
			&b.CreatedAt,
		)
		b.Images = []string{}
		bookings = append(bookings, b)
	}
	if bookings == nil {
		bookings = []Booking{}
	}
	c.JSON(http.StatusOK, gin.H{"bookings": bookings, "total": len(bookings)})
}

// PUT /admin/bookings/:ref/status — update booking status
func adminUpdateBookingStatus(c *gin.Context) {
	ref := c.Param("ref")
	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	validStatuses := map[string]bool{"confirmed": true, "pending": true, "checked_in": true, "completed": true, "cancelled": true}
	if !validStatuses[req.Status] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status"})
		return
	}

	_, err := db.Exec(`UPDATE bookings SET status = $1 WHERE booking_ref = $2`, req.Status, ref)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update status"})
		return
	}

	// A cash booking is confirmed here (not via payment-service's
	// verifyPayment), so this is the only trigger point for its
	// confirmation email and invoice.
	if req.Status == "confirmed" {
		go sendConfirmationEmailForBooking(ref)
		go generateInvoiceForBooking(ref)
	}

	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "BOOKING_STATUS_CHANGED", "booking", ref, "status="+req.Status)

	c.JSON(http.StatusOK, gin.H{"message": "Status updated", "booking_ref": ref, "status": req.Status})
}

// GET /admin/stats — dashboard stats
func adminGetStats(c *gin.Context) {
	var totalBookings, activeBookings, totalUsers, newUsersToday int
	var totalRevenue, todayRevenue float64

	db.QueryRow(`SELECT COUNT(*) FROM bookings`).Scan(&totalBookings)
	db.QueryRow(`SELECT COUNT(*) FROM bookings WHERE status IN ('confirmed','checked_in')`).Scan(&activeBookings)
	db.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status != 'cancelled'`).Scan(&totalRevenue)
	db.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status != 'cancelled' AND DATE(created_at) = CURRENT_DATE`).Scan(&todayRevenue)

	c.JSON(http.StatusOK, gin.H{
		"total_bookings":  totalBookings,
		"active_bookings": activeBookings,
		"total_revenue":   totalRevenue,
		"today_revenue":   todayRevenue,
		"total_users":     totalUsers,
		"new_users_today": newUsersToday,
	})
}

// GET /admin/revenue/weekly — last 7 days revenue
func adminWeeklyRevenue(c *gin.Context) {
	rows, err := db.Query(`
		SELECT TO_CHAR(DATE(created_at), 'Dy') as day,
		       COALESCE(SUM(total_amount), 0) as amount
		FROM bookings
		WHERE status != 'cancelled'
		  AND created_at >= NOW() - INTERVAL '7 days'
		GROUP BY DATE(created_at), TO_CHAR(DATE(created_at), 'Dy')
		ORDER BY DATE(created_at)
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch revenue"})
		return
	}
	defer rows.Close()

	type DayRevenue struct {
		Day    string  `json:"day"`
		Amount float64 `json:"amount"`
	}
	var revenue []DayRevenue
	for rows.Next() {
		var r DayRevenue
		rows.Scan(&r.Day, &r.Amount)
		revenue = append(revenue, r)
	}
	if revenue == nil {
		revenue = []DayRevenue{}
	}
	c.JSON(http.StatusOK, gin.H{"revenue": revenue})
}

// GET /admin/coupons — all coupons
func adminGetCoupons(c *gin.Context) {
	rows, err := db.Query(`
		SELECT id, code, COALESCE(description,''), discount, min_amount,
		       max_uses, used_count, is_active, expires_at
		FROM coupons ORDER BY created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch coupons"})
		return
	}
	defer rows.Close()

	type AdminCoupon struct {
		ID          int       `json:"id"`
		Code        string    `json:"code"`
		Description string    `json:"description"`
		Discount    float64   `json:"discount"`
		MinAmount   int       `json:"min_amount"`
		MaxUses     int       `json:"max_uses"`
		UsedCount   int       `json:"used_count"`
		IsActive    bool      `json:"is_active"`
		ExpiresAt   time.Time `json:"expires_at"`
	}

	var coupons []AdminCoupon
	for rows.Next() {
		var cp AdminCoupon
		rows.Scan(&cp.ID, &cp.Code, &cp.Description, &cp.Discount,
			&cp.MinAmount, &cp.MaxUses, &cp.UsedCount, &cp.IsActive, &cp.ExpiresAt)
		coupons = append(coupons, cp)
	}
	if coupons == nil {
		coupons = []AdminCoupon{}
	}
	c.JSON(http.StatusOK, gin.H{"coupons": coupons})
}

// POST /admin/coupons — create coupon
func adminCreateCoupon(c *gin.Context) {
	var req struct {
		Code        string  `json:"code" binding:"required"`
		Description string  `json:"description"`
		Discount    float64 `json:"discount" binding:"required"`
		MinAmount   int     `json:"min_amount"`
		MaxUses     int     `json:"max_uses"`
		ExpiresAt   string  `json:"expires_at" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.MaxUses == 0 {
		req.MaxUses = 100
	}

	_, err := db.Exec(`
		INSERT INTO coupons (code, description, discount, min_amount, max_uses, used_count, is_active, expires_at)
		VALUES ($1, $2, $3, $4, $5, 0, true, $6)
	`, req.Code, req.Description, req.Discount, req.MinAmount, req.MaxUses, req.ExpiresAt)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create coupon: " + err.Error()})
		return
	}
	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "COUPON_CREATED", "coupon", req.Code, "")
	c.JSON(http.StatusCreated, gin.H{"message": "Coupon created successfully"})
}

// PUT /admin/coupons/:id/toggle — toggle active status
func adminToggleCoupon(c *gin.Context) {
	id := c.Param("id")
	_, err := db.Exec(`UPDATE coupons SET is_active = NOT is_active WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to toggle coupon"})
		return
	}
	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "COUPON_TOGGLED", "coupon", id, "")
	c.JSON(http.StatusOK, gin.H{"message": "Coupon status toggled"})
}

// DELETE /admin/coupons/:id — delete coupon
func adminDeleteCoupon(c *gin.Context) {
	id := c.Param("id")
	_, err := db.Exec(`DELETE FROM coupons WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete coupon"})
		return
	}
	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "COUPON_DELETED", "coupon", id, "")
	c.JSON(http.StatusOK, gin.H{"message": "Coupon deleted"})
}

// POST /admin/notifications/send — broadcast notification to users
func adminSendNotification(c *gin.Context) {
	var req struct {
		Title  string `json:"title" binding:"required"`
		Body   string `json:"body" binding:"required"`
		Target string `json:"target"` // "all", "active", "new"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Target == "" {
		req.Target = "all"
	}

	// Build query based on target
	var query string
	switch req.Target {
	case "active":
		query = `SELECT DISTINCT u.fcm_token FROM users u
			JOIN bookings b ON b.phone = u.phone
			WHERE u.fcm_token IS NOT NULL AND u.fcm_token != ''
			AND b.status IN ('confirmed', 'pending')`
	case "new":
		query = `SELECT fcm_token FROM users
			WHERE fcm_token IS NOT NULL AND fcm_token != ''
			AND created_at >= NOW() - INTERVAL '7 days'`
	default: // all
		query = `SELECT fcm_token FROM users
			WHERE fcm_token IS NOT NULL AND fcm_token != ''`
	}

	rows, err := db.Query(query)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch users"})
		return
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		rows.Scan(&token)
		if token != "" {
			tokens = append(tokens, token)
		}
	}

	// Send notifications in background
	sent := 0
	for _, token := range tokens {
		go sendFCMNotification(token, req.Title, req.Body)
		sent++
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("Notification sent to %d users", sent),
		"sent":    sent,
		"target":  req.Target,
	})
}

// DELETE /admin/bookings/cancelled — clear cancelled bookings older than 30 days
func adminClearCancelledBookings(c *gin.Context) {
	// Bookings with an unsettled refund are skipped — see
	// deleteBooking for why.
	result, err := db.Exec(`
		DELETE FROM bookings b
		WHERE b.status = 'cancelled'
		  AND b.updated_at < NOW() - INTERVAL '30 days'
		  AND NOT EXISTS (
		      SELECT 1 FROM refunds r
		      WHERE r.booking_ref = b.booking_ref
		        AND r.status IN ` + unsettledRefundStatuses + `
		  )
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to clear bookings"})
		return
	}
	rows, _ := result.RowsAffected()
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("Cleared %d cancelled bookings", rows),
		"deleted": rows,
		"skipped": countRefundBlockedBookings(),
	})
}

// countRefundBlockedBookings reports how many cancelled
// bookings were retained because money is still owed.
func countRefundBlockedBookings() int {
	var n int
	db.QueryRow(`
		SELECT COUNT(*) FROM bookings b
		JOIN refunds r ON r.booking_ref = b.booking_ref
		WHERE b.status = 'cancelled'
		  AND r.status IN ` + unsettledRefundStatuses).Scan(&n)
	return n
}
func adminClearAllCancelledBookings(c *gin.Context) {
	skipped := countRefundBlockedBookings()

	result, err := db.Exec(`
		DELETE FROM bookings b
		WHERE b.status = 'cancelled'
		  AND NOT EXISTS (
		      SELECT 1 FROM refunds r
		      WHERE r.booking_ref = b.booking_ref
		        AND r.status IN ` + unsettledRefundStatuses + `
		  )
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to clear bookings"})
		return
	}
	rows, _ := result.RowsAffected()
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("Cleared %d cancelled bookings", rows),
		"deleted": rows,
		"skipped": skipped,
		"note":    "bookings with an unsettled refund are retained until the refund settles",
	})
}

package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/oauth2/google"
)

// ── Send FCM notification via V1 API ─────────────────────
func sendFCMNotification(fcmToken, title, body string) {
	// Read service account JSON
	serviceAccountPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT")
	if serviceAccountPath == "" {
		serviceAccountPath = "./firebase-service-account.json"
	}

	serviceAccountJSON, err := os.ReadFile(serviceAccountPath)
	if err != nil {
		fmt.Printf("⚠️ FCM: Could not read service account: %v\n", err)
		return
	}

	// Get OAuth2 token
	conf, err := google.CredentialsFromJSON(
		context.Background(),
		serviceAccountJSON,
		"https://www.googleapis.com/auth/firebase.messaging",
	)
	if err != nil {
		fmt.Printf("⚠️ FCM: Could not create credentials: %v\n", err)
		return
	}

	token, err := conf.TokenSource.Token()
	if err != nil {
		fmt.Printf("⚠️ FCM: Could not get token: %v\n", err)
		return
	}

	// Build FCM message
	projectID := "kumbh-tent-19e88"
	url := fmt.Sprintf(
		"https://fcm.googleapis.com/v1/projects/%s/messages:send",
		projectID,
	)

	message := map[string]interface{}{
		"message": map[string]interface{}{
			"token": fcmToken,
			"notification": map[string]string{
				"title": title,
				"body":  body,
			},
			"android": map[string]interface{}{
				"notification": map[string]string{
					"channel_id": "bharat_tent_channel",
					"icon":       "ic_launcher",
				},
			},
		},
	}

	msgJSON, _ := json.Marshal(message)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(msgJSON))
	req.Header.Set("Authorization", "Bearer "+token.AccessToken)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("⚠️ FCM: Request failed: %v\n", err)
		return
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 200 {
		fmt.Printf("✅ FCM notification sent successfully\n")
	} else {
		fmt.Printf("⚠️ FCM notification failed: %s\n", string(respBody))
	}
}

func verifyPayment(c *gin.Context) {
	phone := verifiedPhone(c)
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		BookingRef        string `json:"booking_ref" binding:"required"`
		RazorpayPaymentID string `json:"razorpay_payment_id" binding:"required"`
		RazorpayOrderID   string `json:"razorpay_order_id" binding:"required"`
		RazorpaySignature string `json:"razorpay_signature" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify Razorpay signature. RAZORPAY_KEY_SECRET is verified at
	// startup (requireEnv in main), so there is no fallback here — a
	// missing secret must never silently degrade signature checking.
	secret := os.Getenv("RAZORPAY_KEY_SECRET")

	payload := req.RazorpayOrderID + "|" + req.RazorpayPaymentID
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	expectedSig := hex.EncodeToString(mac.Sum(nil))

	if expectedSig != req.RazorpaySignature {
		db.Exec(`
			INSERT INTO payments (booking_ref, razorpay_order, razorpay_payment, razorpay_signature, status)
			VALUES ($1, $2, $3, $4, 'failed')
		`, req.BookingRef, req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature)
		c.JSON(http.StatusBadRequest, gin.H{"error": "payment verification failed"})
		return
	}

	// Fetch booking details needed for the confirmation email/push/invoice
	var (
		amount, baseAmount, discount, tax float64
		tentName, location, currency      string
		checkInDate                       time.Time
		checkOutDate                      time.Time
		nights, guests                    int
		guestName                         sql.NullString
	)
	err := db.QueryRow(`
		SELECT total_amount, tent_name, COALESCE(location,''),
		       check_in, check_out, nights, guests, guest_name,
		       base_amount, discount, tax, currency
		FROM bookings
		WHERE booking_ref = $1 AND phone = $2
	`, req.BookingRef, phone).Scan(
		&amount, &tentName, &location,
		&checkInDate, &checkOutDate, &nights, &guests, &guestName,
		&baseAmount, &discount, &tax, &currency,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	checkIn := checkInDate.Format("2 Jan 2006")
	checkOut := checkOutDate.Format("2 Jan 2006")

	// BUG-28: the payment INSERT and the booking status UPDATE used
	// to be two separate, unrelated db.Exec calls. A crash or lost
	// connection between them left a 'success' payment row pointing
	// at a booking that was still 'pending' forever — the customer
	// was charged but their booking never confirmed, with no
	// automatic way to reconcile the two. Both writes now happen in
	// one transaction, so either both land or neither does.
	tx, err := db.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback()

	// Save payment record
	_, err = tx.Exec(`
		INSERT INTO payments
			(booking_ref, razorpay_order, razorpay_payment, razorpay_signature, amount, status)
		VALUES ($1, $2, $3, $4, $5, 'success')
	`, req.BookingRef, req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature, amount)
	if err != nil {
		// BUG-27: a UNIQUE index (migrations/016) now rejects a second
		// 'success' row for the same razorpay_payment — this call is a
		// duplicate (retry/webhook race) of one that already went
		// through. Report it as the success it already is instead of
		// a 500, without writing anything twice.
		if isUniqueViolation(err, "razorpay_payment") {
			tx.Rollback()
			c.JSON(http.StatusOK, gin.H{
				"message":     "Payment already verified! Booking confirmed 🪔",
				"booking_ref": req.BookingRef,
				"payment_id":  req.RazorpayPaymentID,
				"status":      "confirmed",
				"verified_at": time.Now(),
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save payment"})
		return
	}

	// Update booking status to confirmed. Only a still-pending row
	// flips — so a duplicate/retried verify call is a no-op here and
	// does not double-count the coupon below (BUG-07). Runs inside
	// the same transaction as the payment INSERT above (BUG-28).
	res, err := tx.Exec(`
		UPDATE bookings
		SET status = 'confirmed', payment_id = $1, updated_at = NOW()
		WHERE booking_ref = $2 AND status = 'pending'
	`, req.RazorpayPaymentID, req.BookingRef)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to confirm booking"})
		return
	}
	bookingConfirmedNow, _ := res.RowsAffected()

	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit payment confirmation"})
		return
	}

	// BUG-07: burn the coupon use only now that the booking is
	// actually paid — createBooking no longer does it at 'pending'
	// time (where an abandoned booking would eat a use forever).
	if rows, _ := res.RowsAffected(); rows > 0 {
		db.Exec(`
			UPDATE coupons SET used_count = used_count + 1
			WHERE code = (SELECT coupon_code FROM bookings WHERE booking_ref = $1)
			  AND code IS NOT NULL AND code <> ''
		`, req.BookingRef)
	}

	fmt.Printf("✅ Payment verified for booking %s | Payment ID: %s\n",
		req.BookingRef, req.RazorpayPaymentID)

	if bookingConfirmedNow == 0 {
		// Booking was already something other than 'pending' (already
		// confirmed, or cancelled out from under this payment) — the
		// payment record is saved either way, but skip re-sending the
		// confirmation email/push/invoice/ledger entry below.
		c.JSON(http.StatusOK, gin.H{
			"message":     "Payment verified! Booking confirmed 🪔",
			"booking_ref": req.BookingRef,
			"payment_id":  req.RazorpayPaymentID,
			"status":      "confirmed",
			"verified_at": time.Now(),
		})
		return
	}

	// ── Send FCM notification ──────────────────────────────
	go func() {
		var fcmToken string
		err := db.QueryRow(`
			SELECT COALESCE(fcm_token, '') FROM users WHERE phone = $1
		`, phone).Scan(&fcmToken)
		if err == nil && fcmToken != "" {
			sendFCMNotification(
				fcmToken,
				"🪔 Booking Confirmed!",
				fmt.Sprintf("Your booking for %s (Ref: %s) is confirmed. ₹%.0f paid successfully.",
					tentName, req.BookingRef, amount),
			)
		}
	}()

	// ── Send booking confirmation email ────────────────────
	go func() {
		var userEmail string
		if err := db.QueryRow(`
			SELECT COALESCE(email, '') FROM users WHERE phone = $1
		`, phone).Scan(&userEmail); err == nil && userEmail != "" {
			sendBookingConfirmationEmail(
				userEmail, guestName.String, req.BookingRef, tentName, location,
				checkIn, checkOut, nights, guests, amount,
			)
		}
	}()

	// ── Generate the invoice ───────────────────────────────
	// (ISO dates here, not the "2 Jan 2006" display format used
	// for the email — this goes into a DATE column.)
	go generateInvoiceForBooking(
		req.BookingRef, phone, tentName, location, currency,
		checkInDate.Format("2006-01-02"), checkOutDate.Format("2006-01-02"), guestName.String,
		baseAmount, discount, tax, amount,
	)

	// ── Post the ledger entry ──────────────────────────────
	// Bank/Gateway Dr, Customer/Revenue Cr — the exact example
	// from the accounting module's spec.
	go postLedgerPair(
		time.Now().Format("2006-01-02"), "booking_payment", req.BookingRef,
		"Bank/Gateway", "Customer/Revenue", amount,
		fmt.Sprintf("Payment for %s (%s)", tentName, req.BookingRef),
	)

	c.JSON(http.StatusOK, gin.H{
		"message":     "Payment verified! Booking confirmed 🪔",
		"booking_ref": req.BookingRef,
		"payment_id":  req.RazorpayPaymentID,
		"status":      "confirmed",
		"verified_at": time.Now(),
	})
}

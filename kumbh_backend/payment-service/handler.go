package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
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
					"channel_id": "kumbh_tent_channel",
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
	phone := c.GetHeader("X-User-Phone")
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

	// Verify Razorpay signature
	secret := os.Getenv("RAZORPAY_KEY_SECRET")
	if secret == "" {
		secret = "test_secret"
	}

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

	// Fetch booking amount and tent name
	var amount float64
	var tentName string
	err := db.QueryRow(`
		SELECT total_amount, tent_name FROM bookings 
		WHERE booking_ref = $1 AND phone = $2
	`, req.BookingRef, phone).Scan(&amount, &tentName)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	// Save payment record
	_, err = db.Exec(`
		INSERT INTO payments
			(booking_ref, razorpay_order, razorpay_payment, razorpay_signature, amount, status)
		VALUES ($1, $2, $3, $4, $5, 'success')
	`, req.BookingRef, req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature, amount)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save payment"})
		return
	}

	// Update booking status to confirmed
	_, err = db.Exec(`
		UPDATE bookings
		SET status = 'confirmed', payment_id = $1, updated_at = NOW()
		WHERE booking_ref = $2
	`, req.RazorpayPaymentID, req.BookingRef)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to confirm booking"})
		return
	}

	fmt.Printf("✅ Payment verified for booking %s | Payment ID: %s\n",
		req.BookingRef, req.RazorpayPaymentID)

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

	c.JSON(http.StatusOK, gin.H{
		"message":     "Payment verified! Booking confirmed 🪔",
		"booking_ref": req.BookingRef,
		"payment_id":  req.RazorpayPaymentID,
		"status":      "confirmed",
		"verified_at": time.Now(),
	})
}
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

// createRazorpayOrder calls Razorpay Orders API and returns the order ID to Flutter
func createRazorpayOrder(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		BookingRef string `json:"booking_ref" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Fetch booking from DB — verify it belongs to this user and is still pending
	var totalAmount float64
	var status string
	err := db.QueryRow(`
		SELECT total_amount, status FROM bookings
		WHERE booking_ref = $1 AND phone = $2
	`, req.BookingRef, phone).Scan(&totalAmount, &status)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	if status != "pending" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("booking is already %s", status),
		})
		return
	}

	// Call Razorpay Orders API
	keyID := os.Getenv("RAZORPAY_KEY_ID")
	keySecret := os.Getenv("RAZORPAY_KEY_SECRET")
	if keyID == "" || keySecret == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "payment config missing"})
		return
	}

	// BUG-11: round, don't truncate. int(x*100) on a value like
	// 8850.00 that floats to 8849.9999999 silently drops a paisa,
	// so the Razorpay order is ₹0.01 short of the booking total.
	amountPaise := int(math.Round(totalAmount * 100)) // Razorpay uses paise

	payload := map[string]interface{}{
		"amount":          amountPaise,
		"currency":        "INR",
		"receipt":         req.BookingRef,
		"payment_capture": 1,
		"notes": map[string]string{
			"booking_ref": req.BookingRef,
			"phone":       phone,
		},
	}
	body, _ := json.Marshal(payload)

	rzpReq, err := http.NewRequest("POST", "https://api.razorpay.com/v1/orders", bytes.NewBuffer(body))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to build request"})
		return
	}
	rzpReq.SetBasicAuth(keyID, keySecret)
	rzpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(rzpReq)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to reach Razorpay"})
		return
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		fmt.Printf("❌ Razorpay order creation failed: %s\n", string(respBody))
		c.JSON(http.StatusBadGateway, gin.H{"error": "Razorpay order creation failed"})
		return
	}

	var rzpOrder map[string]interface{}
	if err := json.Unmarshal(respBody, &rzpOrder); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid Razorpay response"})
		return
	}

	razorpayOrderID, ok := rzpOrder["id"].(string)
	if !ok || razorpayOrderID == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "missing order ID in Razorpay response"})
		return
	}

	// Store the Razorpay order ID against the booking so verifyPayment can cross-check it
	_, err = db.Exec(`
		UPDATE bookings SET razorpay_order_id = $1, updated_at = NOW()
		WHERE booking_ref = $2
	`, razorpayOrderID, req.BookingRef)
	if err != nil {
		// Non-fatal — log and continue; verifyPayment still works via signature check
		fmt.Printf("⚠️  Could not store razorpay_order_id for %s: %v\n", req.BookingRef, err)
	}

	fmt.Printf("✅ Razorpay order created: %s for booking %s (₹%.0f)\n",
		razorpayOrderID, req.BookingRef, totalAmount)

	c.JSON(http.StatusOK, gin.H{
		"razorpay_order_id": razorpayOrderID,
		"amount":            amountPaise,
		"currency":          "INR",
		"booking_ref":       req.BookingRef,
	})
}

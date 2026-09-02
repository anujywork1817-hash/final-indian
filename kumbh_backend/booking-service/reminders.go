package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"golang.org/x/oauth2/google"
)

// sendFCMNotification sends a push notification via FCM V1 API
func sendFCMNotification(fcmToken, title, body string) {
	var serviceAccountJSON []byte

	if jsonStr := os.Getenv("FIREBASE_SERVICE_ACCOUNT_JSON"); jsonStr != "" {
		serviceAccountJSON = []byte(jsonStr)
	} else {
		path := os.Getenv("FIREBASE_SERVICE_ACCOUNT")
		if path == "" {
			path = "./firebase-service-account.json"
		}
		var err error
		serviceAccountJSON, err = os.ReadFile(path)
		if err != nil {
			fmt.Printf("⚠️ FCM: Could not read service account: %v\n", err)
			return
		}
	}

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
		fmt.Printf("✅ FCM reminder sent to token: %s...\n", fcmToken[:20])
	} else {
		fmt.Printf("⚠️ FCM reminder failed: %s\n", string(respBody))
	}
}

// sendBookingReminders sends reminders and auto-completes past bookings
func sendBookingReminders() {
	now := time.Now().UTC()
	today := now.Format("2006-01-02")
	tomorrow := now.Add(24 * time.Hour).Format("2006-01-02")

	fmt.Printf("📅 Running booking reminders for %s\n", today)

	// ── Auto-complete past bookings ────────────────────────
	result, err := db.Exec(`
		UPDATE bookings 
		SET status = 'completed', updated_at = NOW()
		WHERE status = 'confirmed' 
		AND check_out < $1
	`, today)
	if err != nil {
		fmt.Printf("⚠️ Auto-complete failed: %v\n", err)
	} else {
		rows, _ := result.RowsAffected()
		if rows > 0 {
			fmt.Printf("✅ Auto-completed %d past bookings\n", rows)
		}
	}

	// ── Send completion notification ───────────────────────
	completedRows, err := db.Query(`
		SELECT b.booking_ref, b.tent_name, COALESCE(u.fcm_token, '')
		FROM bookings b
		JOIN users u ON u.phone = b.phone
		WHERE b.status = 'completed'
		  AND b.check_out = $1
		  AND u.fcm_token IS NOT NULL
		  AND u.fcm_token != ''
	`, today)
	if err == nil {
		defer completedRows.Close()
		for completedRows.Next() {
			var bookingRef, tentName, fcmToken string
			completedRows.Scan(&bookingRef, &tentName, &fcmToken)
			if fcmToken == "" {
				continue
			}
			go sendFCMNotification(
				fcmToken,
				"🙏 Thank you for staying!",
				fmt.Sprintf("We hope you enjoyed your stay at %s. Please rate your experience! Ref: %s", tentName, bookingRef),
			)
		}
	}

	// ── Tomorrow check-in reminders ────────────────────────
	rows, err := db.Query(`
		SELECT b.booking_ref, b.tent_name, b.location, b.check_in,
		       b.total_amount, b.status, COALESCE(u.fcm_token, '')
		FROM bookings b
		JOIN users u ON u.phone = b.phone
		WHERE b.check_in = $1
		  AND b.status = 'confirmed'
		  AND u.fcm_token IS NOT NULL
		  AND u.fcm_token != ''
	`, tomorrow)
	if err != nil {
		fmt.Printf("⚠️ Reminder query failed: %v\n", err)
		return
	}
	defer rows.Close()

	tomorrowCount := 0
	for rows.Next() {
		var bookingRef, tentName, location, checkIn, status, fcmToken string
		var totalAmount float64
		rows.Scan(&bookingRef, &tentName, &location, &checkIn, &totalAmount, &status, &fcmToken)
		if fcmToken == "" {
			continue
		}
		go sendFCMNotification(
			fcmToken,
			"🪔 Check-in Tomorrow!",
			fmt.Sprintf("Your stay at %s begins tomorrow. Ref: %s. Don't forget your e-ticket!", tentName, bookingRef),
		)
		tomorrowCount++
	}
	fmt.Printf("✅ Sent %d tomorrow check-in reminders\n", tomorrowCount)

	// ── Today check-in reminders ───────────────────────────
	rows2, err := db.Query(`
		SELECT b.booking_ref, b.tent_name, b.location, b.check_in,
		       b.total_amount, b.status, COALESCE(u.fcm_token, '')
		FROM bookings b
		JOIN users u ON u.phone = b.phone
		WHERE b.check_in = $1
		  AND b.status = 'confirmed'
		  AND u.fcm_token IS NOT NULL
		  AND u.fcm_token != ''
	`, today)
	if err != nil {
		fmt.Printf("⚠️ Today reminder query failed: %v\n", err)
		return
	}
	defer rows2.Close()

	todayCount := 0
	for rows2.Next() {
		var bookingRef, tentName, location, checkIn, status, fcmToken string
		var totalAmount float64
		rows2.Scan(&bookingRef, &tentName, &location, &checkIn, &totalAmount, &status, &fcmToken)
		if fcmToken == "" {
			continue
		}
		go sendFCMNotification(
			fcmToken,
			"⏰ Check-in Today!",
			fmt.Sprintf("Welcome to %s! Show your e-ticket QR at the entrance. Ref: %s 🪔", tentName, bookingRef),
		)
		todayCount++
	}
	fmt.Printf("✅ Sent %d today check-in reminders\n", todayCount)

	// ── Pay at Tent payment reminders ──────────────────────
	rows3, err := db.Query(`
		SELECT b.booking_ref, b.tent_name, b.total_amount, COALESCE(u.fcm_token, '')
		FROM bookings b
		JOIN users u ON u.phone = b.phone
		WHERE b.check_in = $1
		  AND b.status = 'pending'
		  AND b.payment_id = 'CASH'
		  AND u.fcm_token IS NOT NULL
		  AND u.fcm_token != ''
	`, tomorrow)
	if err == nil {
		defer rows3.Close()
		cashCount := 0
		for rows3.Next() {
			var bookingRef, tentName, fcmToken string
			var totalAmount float64
			rows3.Scan(&bookingRef, &tentName, &totalAmount, &fcmToken)
			if fcmToken == "" {
				continue
			}
			go sendFCMNotification(
				fcmToken,
				"💰 Payment Reminder",
				fmt.Sprintf("Don't forget! Pay ₹%.0f cash at %s tomorrow. Ref: %s", totalAmount, tentName, bookingRef),
			)
			cashCount++
		}
		fmt.Printf("✅ Sent %d cash payment reminders\n", cashCount)
	}

	// ── Auto-delete cancelled bookings older than 30 days ──
	// Bookings with an unsettled refund are retained: deleting
	// them would erase the customer's only view of money still
	// owed to them, and the staff context needed to pay it.
	deleted, err := db.Exec(`
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
		fmt.Printf("⚠️ Auto-delete cancelled failed: %v\n", err)
	} else {
		rows, _ := deleted.RowsAffected()
		if rows > 0 {
			fmt.Printf("✅ Auto-deleted %d cancelled bookings older than 30 days\n", rows)
		}
	}

	if blocked := countRefundBlockedBookings(); blocked > 0 {
		fmt.Printf("📋 Retained %d cancelled booking(s) with unsettled refunds\n", blocked)
	}
}

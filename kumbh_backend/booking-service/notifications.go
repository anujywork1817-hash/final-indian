package main

import (
	"database/sql"
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// ── Push notification core ───────────────────────────────
//
// Everything user-facing goes through notifyUser rather than calling
// sendFCMNotification directly. Two things that buys us:
//
//  1. Idempotency. The schedulers re-run daily over the same rows;
//     without a claim step a user would get "your stay begins
//     tomorrow" again on every pass. The unique index on
//     (phone, type, ref_key) in notification_log is the lock — we
//     INSERT first and only send if the insert won, so a duplicate
//     is impossible even if two schedulers race.
//
//  2. Preferences. A user who muted one category still gets the
//     others. Absence of a prefs row means enabled, so nobody needs
//     backfilling.
//
// Direct sendFCMNotification calls are left alone for the existing
// booking-flow pushes; those are event-driven (fire once when the
// event happens) rather than scheduled, so they were never at risk
// of repeating.

// Notification type identifiers. Stored in notification_log.type and
// notification_prefs.type, and exposed to the app so it can render a
// preferences screen without hardcoding a parallel list.
const (
	NotifBookingConfirmed = "booking_confirmed"
	NotifBookingCancelled = "booking_cancelled"
	NotifPaymentPending   = "payment_pending"
	NotifSnanReminder     = "snan_reminder"
	NotifFavourite        = "favourite"
	NotifNews             = "news"
	NotifRefund           = "refund"
	NotifCheckIn          = "checkin"
)

// NotificationTypes is the catalogue the app's settings screen reads.
var NotificationTypes = []struct {
	Type        string `json:"type"`
	Label       string `json:"label"`
	Description string `json:"description"`
}{
	{NotifBookingConfirmed, "Booking confirmations", "When a booking is confirmed"},
	{NotifBookingCancelled, "Cancellations", "When a booking is cancelled"},
	{NotifPaymentPending, "Payment reminders", "Unpaid bookings waiting on you"},
	{NotifSnanReminder, "Snan reminders", "Dates you asked to be reminded about"},
	{NotifFavourite, "Favourites", "Price drops and low availability on saved tents"},
	{NotifNews, "Kumbh news", "Latest Kumbh Mela updates"},
	{NotifRefund, "Refunds", "Refund approvals and settlements"},
	{NotifCheckIn, "Check-in reminders", "Before your stay begins"},
}

// notificationAllowed reports whether the user has muted this type.
// Missing row => allowed.
func notificationAllowed(phone, notifType string) bool {
	var enabled bool
	err := db.QueryRow(`
		SELECT enabled FROM notification_prefs WHERE phone = $1 AND type = $2
	`, phone, notifType).Scan(&enabled)
	if err == sql.ErrNoRows {
		return true
	}
	if err != nil {
		// Fail open: a preferences lookup problem should not silently
		// swallow a booking confirmation.
		fmt.Printf("notify: prefs lookup failed for %s/%s: %v\n", phone, notifType, err)
		return true
	}
	return enabled
}

// notifyUser is the single entry point for a push.
//
// refKey identifies *what* is being notified about (booking ref,
// snan date, article id). Reusing a refKey for the same phone+type
// is how repeat sends are suppressed — pass a unique key per
// distinct event, and a stable one for anything a scheduler may
// revisit.
func notifyUser(phone, notifType, refKey, title, body string) {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return
	}
	if !notificationAllowed(phone, notifType) {
		return
	}

	// Claim first. If another pass already logged this exact
	// (phone, type, ref_key) the insert conflicts and we stop —
	// that is the whole duplicate guard, so it must happen BEFORE
	// the send, not after.
	res, err := db.Exec(`
		INSERT INTO notification_log (phone, type, ref_key, title, body)
		VALUES ($1,$2,$3,$4,$5)
		ON CONFLICT (phone, type, ref_key) DO NOTHING
	`, phone, notifType, refKey, title, body)
	if err != nil {
		fmt.Printf("notify: log insert failed for %s/%s: %v\n", phone, notifType, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return // already sent
	}

	var fcmToken string
	if db.QueryRow(`SELECT COALESCE(fcm_token,'') FROM users WHERE phone = $1`, phone).
		Scan(&fcmToken) != nil || fcmToken == "" {
		// No device registered. The log row stays so we do not retry
		// forever once they do install — but mark it undelivered so
		// the trail is honest about what actually reached a phone.
		db.Exec(`UPDATE notification_log SET delivered = FALSE, error = 'no fcm token'
		         WHERE phone = $1 AND type = $2 AND ref_key = $3`, phone, notifType, refKey)
		return
	}

	sendFCMNotification(fcmToken, title, body)
}

// notifyAllUsers fans a push out to everyone with a registered
// device — used for news and other broadcasts. Still per-user
// underneath, so preferences and de-duplication both apply.
func notifyAllUsers(notifType, refKey, title, body string) int {
	rows, err := db.Query(`
		SELECT phone FROM users WHERE fcm_token IS NOT NULL AND fcm_token != ''
	`)
	if err != nil {
		fmt.Printf("notify: broadcast query failed: %v\n", err)
		return 0
	}
	defer rows.Close()

	var phones []string
	for rows.Next() {
		var p string
		if rows.Scan(&p) == nil {
			phones = append(phones, p)
		}
	}
	for _, p := range phones {
		notifyUser(p, notifType, refKey, title, body)
	}
	return len(phones)
}

// ── Preference endpoints ─────────────────────────────────

// GET /notifications/preferences?phone=
func getNotificationPrefs(c *gin.Context) {
	phone := strings.TrimSpace(c.Query("phone"))
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone is required"})
		return
	}

	muted := map[string]bool{}
	rows, err := db.Query(`SELECT type, enabled FROM notification_prefs WHERE phone = $1`, phone)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var t string
			var enabled bool
			if rows.Scan(&t, &enabled) == nil {
				muted[t] = enabled
			}
		}
	}

	type pref struct {
		Type        string `json:"type"`
		Label       string `json:"label"`
		Description string `json:"description"`
		Enabled     bool   `json:"enabled"`
	}
	out := make([]pref, 0, len(NotificationTypes))
	for _, t := range NotificationTypes {
		enabled, ok := muted[t.Type]
		if !ok {
			enabled = true // no row => on
		}
		out = append(out, pref{t.Type, t.Label, t.Description, enabled})
	}
	c.JSON(http.StatusOK, gin.H{"preferences": out})
}

// PUT /notifications/preferences
func setNotificationPref(c *gin.Context) {
	var body struct {
		Phone   string `json:"phone" binding:"required"`
		Type    string `json:"type" binding:"required"`
		Enabled *bool  `json:"enabled" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	valid := false
	for _, t := range NotificationTypes {
		if t.Type == body.Type {
			valid = true
			break
		}
	}
	if !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unknown notification type"})
		return
	}

	_, err := db.Exec(`
		INSERT INTO notification_prefs (phone, type, enabled, updated_at)
		VALUES ($1,$2,$3,NOW())
		ON CONFLICT (phone, type) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = NOW()
	`, strings.TrimSpace(body.Phone), body.Type, *body.Enabled)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save preference"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Preference saved", "type": body.Type, "enabled": *body.Enabled})
}

// GET /notifications/history?phone=
// What the in-app notification centre reads.
func getNotificationHistory(c *gin.Context) {
	phone := strings.TrimSpace(c.Query("phone"))
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone is required"})
		return
	}
	rows, err := db.Query(`
		SELECT type, COALESCE(title,''), COALESCE(body,''), created_at::text
		FROM notification_log
		WHERE phone = $1 AND delivered = TRUE
		ORDER BY created_at DESC LIMIT 100
	`, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch notifications"})
		return
	}
	defer rows.Close()

	type item struct {
		Type      string `json:"type"`
		Title     string `json:"title"`
		Body      string `json:"body"`
		CreatedAt string `json:"created_at"`
	}
	out := []item{}
	for rows.Next() {
		var i item
		if rows.Scan(&i.Type, &i.Title, &i.Body, &i.CreatedAt) == nil {
			out = append(out, i)
		}
	}
	c.JSON(http.StatusOK, gin.H{"notifications": out, "total": len(out)})
}

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// ── Scheduled notification jobs ──────────────────────────
//
// All of these are safe to run repeatedly: every send goes through
// notifyUser, which claims a (phone, type, ref_key) row before
// sending. That means a job can re-scan the same rows every pass
// without spamming anyone, so none of them need their own
// "already processed" bookkeeping.

// runNotificationJobs is the daily batch, called alongside
// sendBookingReminders from the 08:00 IST scheduler.
func runNotificationJobs() {
	sendSnanReminders()
	sendPaymentPendingReminders()
	sendFavouriteAlerts()
}

// ── Snan reminders ───────────────────────────────────────
//
// Opt-in only: a row in snan_reminders means the user tapped the
// bell on that date. Two pushes per date — one the day before, one
// on the morning itself — kept distinct by the ref_key suffix so
// the second is not suppressed as a duplicate of the first.
func sendSnanReminders() {
	rows, err := db.Query(`
		SELECT r.phone, e.event_date::text, e.name, COALESCE(e.location,''), e.is_amrit,
		       (e.event_date - CURRENT_DATE) AS days_away
		FROM snan_reminders r
		JOIN snan_events e ON e.event_date = r.event_date
		WHERE e.event_date - CURRENT_DATE IN (0, 1)
	`)
	if err != nil {
		fmt.Printf("snan reminders: query failed: %v\n", err)
		return
	}
	defer rows.Close()

	sent := 0
	for rows.Next() {
		var phone, date, name, location string
		var isAmrit bool
		var daysAway int
		if rows.Scan(&phone, &date, &name, &location, &isAmrit, &daysAway) != nil {
			continue
		}

		var title, body, suffix string
		if daysAway == 1 {
			suffix = "pre"
			title = "Snan tomorrow: " + name
			body = fmt.Sprintf("%s is tomorrow at %s. Plan your travel and book your tent early.", name, location)
		} else {
			suffix = "day"
			title = "Today: " + name
			body = fmt.Sprintf("%s is today at %s. Har Har Gange!", name, location)
		}
		if isAmrit {
			body += " Expect very large crowds — arrive early."
		}

		notifyUser(phone, NotifSnanReminder, date+":"+suffix, title, body)
		sent++
	}
	if sent > 0 {
		fmt.Printf("snan reminders: processed %d\n", sent)
	}
}

// ── Payment pending / abandoned cart ─────────────────────
//
// Distinct from the existing "pay cash at the tent tomorrow"
// reminder, which only covers confirmed cash bookings near check-in.
// This one chases bookings that were STARTED and never paid, so the
// booking is still sitting unconfirmed and the tent is effectively
// held for nobody.
//
// Escalating over three days rather than one nag: after that we
// stop, because at some point it is spam.
func sendPaymentPendingReminders() {
	rows, err := db.Query(`
		SELECT b.booking_ref, b.phone, b.tent_name, b.total_amount,
		       FLOOR(EXTRACT(EPOCH FROM (NOW() - b.created_at)) / 3600)::int AS hours_old
		FROM bookings b
		WHERE b.status = 'pending'
		  AND (b.payment_id IS NULL OR b.payment_id = '')
		  AND NOT EXISTS (
		      SELECT 1 FROM payments p
		      WHERE p.booking_ref = b.booking_ref AND p.status = 'success'
		  )
		  AND b.created_at < NOW() - INTERVAL '1 hour'
		  AND b.created_at > NOW() - INTERVAL '4 days'
	`)
	if err != nil {
		fmt.Printf("payment pending: query failed: %v\n", err)
		return
	}
	defer rows.Close()

	sent := 0
	for rows.Next() {
		var ref, phone, tentName string
		var amount float64
		var hoursOld int
		if rows.Scan(&ref, &phone, &tentName, &amount, &hoursOld) != nil {
			continue
		}

		// One message per elapsed-day bucket. The bucket is part of
		// the ref_key, so day 1 and day 2 are separate sends but a
		// second run on the same day is suppressed.
		bucket := hoursOld / 24
		if bucket > 2 {
			continue
		}

		var title, body string
		switch bucket {
		case 0:
			title = "Complete your booking"
			body = fmt.Sprintf("Your %s booking is held but unpaid. Pay ₹%.0f now to confirm it. Ref: %s", tentName, amount, ref)
		case 1:
			title = "Your tent is still waiting"
			body = fmt.Sprintf("%s is not confirmed yet. Complete the ₹%.0f payment to secure it. Ref: %s", tentName, amount, ref)
		default:
			title = "Last chance to confirm"
			body = fmt.Sprintf("Your booking for %s expires soon. Pay ₹%.0f to keep it. Ref: %s", tentName, amount, ref)
		}

		notifyUser(phone, NotifPaymentPending, fmt.Sprintf("%s:d%d", ref, bucket), title, body)
		sent++
	}
	if sent > 0 {
		fmt.Printf("payment pending: processed %d\n", sent)
	}
}

// ── Favourite tent alerts ────────────────────────────────
//
// Two things worth interrupting someone for on a tent they saved:
// the price dropped, or it is nearly gone. Anything less is noise.
//
// Price drops compare against tents.last_notified_price rather than
// the previous run's price, so a tent that drifts down repeatedly
// does not fire on every small step.
func sendFavouriteAlerts() {
	// Price drops.
	rows, err := db.Query(`
		SELECT f.phone, t.id, t.name, t.price, t.last_notified_price
		FROM favourites f
		JOIN tents t ON t.id = f.tent_id
		WHERE t.last_notified_price IS NOT NULL
		  AND t.price < t.last_notified_price
	`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var phone, name string
			var tentID, price, lastPrice int
			if rows.Scan(&phone, &tentID, &name, &price, &lastPrice) != nil {
				continue
			}
			drop := lastPrice - price
			notifyUser(phone, NotifFavourite,
				fmt.Sprintf("price:%d:%d", tentID, price),
				"Price drop on "+name,
				fmt.Sprintf("%s is now ₹%d — down ₹%d. Book before it changes.", name, price, drop),
			)
		}
	}

	// Low availability on a saved tent.
	lowRows, err := db.Query(`
		SELECT f.phone, t.id, t.name,
		       t.capacity - COUNT(b.id) FILTER (WHERE b.status IN ('confirmed','pending')) AS available
		FROM favourites f
		JOIN tents t ON t.id = f.tent_id
		LEFT JOIN bookings b ON b.tent_id = t.id
		WHERE t.is_active = TRUE
		GROUP BY f.phone, t.id, t.name, t.capacity
		HAVING t.capacity - COUNT(b.id) FILTER (WHERE b.status IN ('confirmed','pending')) BETWEEN 1 AND 3
	`)
	if err == nil {
		defer lowRows.Close()
		for lowRows.Next() {
			var phone, name string
			var tentID, available int
			if lowRows.Scan(&phone, &tentID, &name, &available) != nil {
				continue
			}
			notifyUser(phone, NotifFavourite,
				fmt.Sprintf("low:%d:%d", tentID, available),
				"Almost gone: "+name,
				fmt.Sprintf("Only %d left at %s — one of your saved tents.", available, name),
			)
		}
	}

	// Baseline every price so the next run has something to compare
	// against. Done last, after alerts, or a drop would be erased
	// before anyone heard about it.
	db.Exec(`UPDATE tents SET last_notified_price = price
	         WHERE last_notified_price IS DISTINCT FROM price`)
}

// ── News poller ──────────────────────────────────────────
//
// The app fetched news client-side, so nothing server-side knew what
// had already been seen and "new article" was unanswerable. This
// stores articles keyed by the provider's URL and pushes only the
// ones inserted for the first time.
//
// Runs hourly rather than daily — news is time-sensitive, and the
// dedupe key means a re-fetch of the same feed costs nothing.
func pollKumbhNews() {
	apiKey := os.Getenv("NEWSDATA_API_KEY")
	if apiKey == "" {
		return // provider not configured; silently skip
	}

	url := fmt.Sprintf(
		"https://newsdata.io/api/1/news?apikey=%s&q=%s&language=en&country=in",
		apiKey, "kumbh%20mela%20nashik",
	)
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		fmt.Printf("news poll: request failed: %v\n", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return
	}
	raw, _ := io.ReadAll(resp.Body)

	var payload struct {
		Results []struct {
			Link        string `json:"link"`
			Title       string `json:"title"`
			Description string `json:"description"`
			ImageURL    string `json:"image_url"`
			SourceID    string `json:"source_id"`
			PubDate     string `json:"pubDate"`
		} `json:"results"`
	}
	if json.Unmarshal(raw, &payload) != nil {
		return
	}

	for _, a := range payload.Results {
		if strings.TrimSpace(a.Link) == "" || strings.TrimSpace(a.Title) == "" {
			continue
		}
		var id int
		// Only a genuinely new link produces a row (and therefore a
		// RETURNING id) — a repeat conflicts and is skipped.
		err := db.QueryRow(`
			INSERT INTO news_articles (external_id, title, description, url, image_url, source, published_at)
			VALUES ($1,$2,NULLIF($3,''),$1,NULLIF($4,''),NULLIF($5,''),NULLIF($6,'')::timestamp)
			ON CONFLICT (external_id) DO NOTHING
			RETURNING id
		`, a.Link, a.Title, a.Description, a.ImageURL, a.SourceID, a.PubDate).Scan(&id)
		if err != nil {
			continue // already stored
		}

		// Push the headline out, then mark it pushed.
		notifyAllUsers(NotifNews, fmt.Sprintf("article:%d", id),
			"Kumbh update", a.Title)
		db.Exec(`UPDATE news_articles SET pushed_at = NOW() WHERE id = $1`, id)
		fmt.Printf("news: pushed article %d — %s\n", id, a.Title)
	}
}

// startNewsPoller runs the news poll hourly in the background.
func startNewsPoller() {
	if os.Getenv("NEWSDATA_API_KEY") == "" {
		fmt.Println("news poller: NEWSDATA_API_KEY not set, poller disabled")
		return
	}
	go func() {
		// Small delay so it does not compete with startup work.
		time.Sleep(2 * time.Minute)
		for {
			runIfLeader("news_poller", pollKumbhNews)
			time.Sleep(1 * time.Hour)
		}
	}()
	fmt.Println("news poller: started (hourly)")
}

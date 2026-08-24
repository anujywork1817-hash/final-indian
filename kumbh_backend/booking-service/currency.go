package main

import (
	"database/sql"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// ── Foreign Currency / Multi-Currency — Phase 3 ──────────
//
// HARD RULE: a booking's exchange_rate and foreign_amount are
// locked at booking-creation time (see lockExchangeRateFor,
// called from createBooking in handler.go) and never
// recalculated. Updating exchange_rates (adminSetExchangeRate)
// only changes what NEW bookings will lock in — it never touches
// an existing bookings row. That is the entire guarantee this
// file exists to enforce; there is deliberately no code path
// anywhere that re-derives a past booking's foreign_amount from
// today's rate.
//
// Tents are priced in INR (bookings.total_amount is always the
// ground truth), so exchange_rate is "how many INR does 1 unit
// of this currency buy" and foreign_amount is a DISPLAY figure —
// total_amount expressed in the customer's currency at the rate
// on the day they booked.

var knownCurrencies = map[string]bool{
	"USD": true, "EUR": true, "GBP": true, "AED": true,
}

// lockExchangeRateFor resolves the rate to lock into a new
// booking. Returns (currency, rate, foreignAmount). For INR (or
// an unrecognized/omitted currency) it returns ("INR", 1, nil) —
// i.e. no foreign_amount is set, matching every booking made
// today through the app's INR-only flow.
func lockExchangeRateFor(currency string, totalAmountINR float64) (string, float64, sql.NullFloat64) {
	code := strings.ToUpper(strings.TrimSpace(currency))
	if code == "" || code == "INR" || !knownCurrencies[code] {
		return "INR", 1, sql.NullFloat64{}
	}
	var rate float64
	if err := db.QueryRow(`SELECT rate_to_inr FROM exchange_rates WHERE currency_code = $1`, code).Scan(&rate); err != nil {
		// No rate configured for this currency — fall back to INR
		// rather than lock in a bogus rate.
		return "INR", 1, sql.NullFloat64{}
	}
	foreign := totalAmountINR / rate
	return code, rate, sql.NullFloat64{Float64: foreign, Valid: true}
}

// GET /admin/exchange-rates
func adminGetExchangeRates(c *gin.Context) {
	rows, err := db.Query(`SELECT currency_code, rate_to_inr, COALESCE(updated_by,''), updated_at FROM exchange_rates ORDER BY currency_code`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch exchange rates"})
		return
	}
	defer rows.Close()

	type rate struct {
		Currency  string  `json:"currency_code"`
		RateToINR float64 `json:"rate_to_inr"`
		UpdatedBy string  `json:"updated_by,omitempty"`
		UpdatedAt string  `json:"updated_at"`
	}
	out := []rate{}
	for rows.Next() {
		var r rate
		var updatedAt sql.NullTime
		if err := rows.Scan(&r.Currency, &r.RateToINR, &r.UpdatedBy, &updatedAt); err == nil {
			if updatedAt.Valid {
				r.UpdatedAt = updatedAt.Time.Format("2006-01-02 15:04:05")
			}
			out = append(out, r)
		}
	}
	c.JSON(http.StatusOK, gin.H{"rates": out})
}

// PUT /admin/exchange-rates/:currency
//
// Sets the CURRENT rate for new bookings only. Deliberately does
// not — and must never — touch bookings.exchange_rate on
// existing rows.
func adminSetExchangeRate(c *gin.Context) {
	code := strings.ToUpper(strings.TrimSpace(c.Param("currency")))
	if !knownCurrencies[code] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported currency — add it to knownCurrencies first"})
		return
	}

	var body struct {
		RateToINR float64 `json:"rate_to_inr" binding:"required"`
		UpdatedBy string  `json:"updated_by"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if body.RateToINR <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "rate_to_inr must be positive"})
		return
	}

	_, err := db.Exec(`
		INSERT INTO exchange_rates (currency_code, rate_to_inr, updated_by, updated_at)
		VALUES ($1, $2, NULLIF($3,''), NOW())
		ON CONFLICT (currency_code) DO UPDATE
			SET rate_to_inr = EXCLUDED.rate_to_inr,
			    updated_by = EXCLUDED.updated_by,
			    updated_at = NOW()
	`, code, body.RateToINR, body.UpdatedBy)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update rate"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "Exchange rate updated for new bookings — existing bookings are unaffected",
		"currency_code": code,
		"rate_to_inr":   body.RateToINR,
	})
}

// GET /admin/finance/fx-report
//
// Foreign Exchange Gain/Loss report: compares each foreign-
// currency booking's LOCKED rate (at booking time) against
// today's rate for that currency, expressed in INR terms.
// Positive gain_loss means the rate has moved in the business's
// favour since the booking (re-pricing today's rate against the
// same foreign_amount would yield more INR); negative means it
// has moved against.
func adminFXReport(c *gin.Context) {
	rows, err := db.Query(`
		SELECT b.booking_ref, b.currency, b.foreign_amount, b.exchange_rate, b.total_amount, b.created_at
		FROM bookings b
		WHERE b.currency != 'INR' AND b.foreign_amount IS NOT NULL
		ORDER BY b.created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch foreign bookings"})
		return
	}
	defer rows.Close()

	currentRates := map[string]float64{}
	rateRows, _ := db.Query(`SELECT currency_code, rate_to_inr FROM exchange_rates`)
	if rateRows != nil {
		for rateRows.Next() {
			var code string
			var rate float64
			if rateRows.Scan(&code, &rate) == nil {
				currentRates[code] = rate
			}
		}
		rateRows.Close()
	}

	type fxRow struct {
		BookingRef       string  `json:"booking_ref"`
		Currency         string  `json:"currency"`
		ForeignAmount    float64 `json:"foreign_amount"`
		BookedRate       float64 `json:"booked_rate"`
		CurrentRate      float64 `json:"current_rate"`
		INRValueAtBooked float64 `json:"inr_value_at_booking"`
		INRValueAtToday  float64 `json:"inr_value_at_current_rate"`
		GainLoss         float64 `json:"gain_loss"`
		BookedAt         string  `json:"booked_at"`
	}

	out := []fxRow{}
	var totalGainLoss float64
	for rows.Next() {
		var r fxRow
		var createdAt sql.NullTime
		if err := rows.Scan(&r.BookingRef, &r.Currency, &r.ForeignAmount, &r.BookedRate, &r.INRValueAtBooked, &createdAt); err != nil {
			continue
		}
		if createdAt.Valid {
			r.BookedAt = createdAt.Time.Format("2006-01-02")
		}
		r.CurrentRate = currentRates[r.Currency]
		if r.CurrentRate == 0 {
			r.CurrentRate = r.BookedRate // no current rate on file — assume unchanged rather than fabricate a swing
		}
		r.INRValueAtToday = r.ForeignAmount * r.CurrentRate
		r.GainLoss = r.INRValueAtToday - r.INRValueAtBooked
		totalGainLoss += r.GainLoss
		out = append(out, r)
	}

	c.JSON(http.StatusOK, gin.H{
		"bookings":        out,
		"total":           len(out),
		"total_gain_loss": totalGainLoss,
	})
}

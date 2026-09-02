package main

import (
	"database/sql"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// DayAvailability is the remaining/total unit count for one calendar
// date, keyed the same way the app's booking calendar renders a day.
type DayAvailability struct {
	Date           string `json:"date"`
	TotalUnits     int    `json:"total_units"`
	BookedUnits    int    `json:"booked_units"`
	RemainingUnits int    `json:"remaining_units"`
}

// dailyAvailability enumerates every date in [start, end) — end is
// exclusive, matching check_in/check_out semantics elsewhere in this
// service — and sums booked units per day from overlapping,
// non-cancelled bookings.
//
// Runs against whatever *sql.DB / *sql.Tx is passed in, so the same
// query backs both the read-only availability endpoint (plain db)
// and createBooking's validation (inside its locked tx) without
// duplicating the SQL.
func dailyAvailability(q queryer, tentID int, start, end string) (totalUnits int, days []DayAvailability, err error) {
	err = q.QueryRow(`SELECT total_units FROM tents WHERE id = $1 AND is_active = TRUE`, tentID).Scan(&totalUnits)
	if err != nil {
		return 0, nil, err
	}

	rows, err := q.Query(`
		SELECT d::date::text, COALESCE(SUM(b.units), 0)
		FROM generate_series($2::date, $3::date - INTERVAL '1 day', INTERVAL '1 day') AS d
		LEFT JOIN bookings b
		       ON b.tent_id = $1
		      AND b.status NOT IN ('cancelled')
		      AND b.check_in <= d
		      AND b.check_out > d
		GROUP BY d
		ORDER BY d
	`, tentID, start, end)
	if err != nil {
		return 0, nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var day DayAvailability
		if err = rows.Scan(&day.Date, &day.BookedUnits); err != nil {
			return 0, nil, err
		}
		day.TotalUnits = totalUnits
		day.RemainingUnits = totalUnits - day.BookedUnits
		days = append(days, day)
	}
	return totalUnits, days, rows.Err()
}

// queryer is the subset of *sql.DB / *sql.Tx that dailyAvailability
// needs, so it can run either standalone (availability endpoint) or
// inside an existing locked transaction (booking validation).
type queryer interface {
	QueryRow(query string, args ...any) *sql.Row
	Query(query string, args ...any) (*sql.Rows, error)
}

// GET /tents/:id/availability?start=YYYY-MM-DD&end=YYYY-MM-DD
//
// Read-only — no lock needed, this is a point-in-time snapshot for
// the calendar UI to color dates with, not something a booking
// commits against. createBooking re-checks for real, under lock,
// at booking time.
func getTentAvailability(c *gin.Context) {
	tentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tent id"})
		return
	}

	start := c.Query("start")
	end := c.Query("end")
	if start == "" || end == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "start and end are required (YYYY-MM-DD)"})
		return
	}
	if _, err := time.Parse("2006-01-02", start); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start date"})
		return
	}
	if _, err := time.Parse("2006-01-02", end); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end date"})
		return
	}

	totalUnits, days, err := dailyAvailability(db, tentID, start, end)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "tent not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch availability"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"tent_id":     tentID,
		"total_units": totalUnits,
		"days":        days,
	})
}

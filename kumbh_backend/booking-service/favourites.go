package main

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ── Favourites ───────────────────────────────────────────
//
// Server-side replacement for the Flutter WishlistStore, which was
// an in-memory Set that did not survive an app restart and was
// invisible to the backend. Persisting it is what makes favourite
// notifications (price drop, running low) possible at all.

// GET /favourites?phone=
func listFavourites(c *gin.Context) {
	phone := strings.TrimSpace(c.Query("phone"))
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone is required"})
		return
	}

	rows, err := db.Query(`
		SELECT t.id, t.name, COALESCE(t.class,''), t.price, COALESCE(t.location,''),
		       t.rating, t.reviews, t.capacity,
		       t.capacity - COUNT(b.id) FILTER (WHERE b.status IN ('confirmed','pending')) AS available
		FROM favourites f
		JOIN tents t ON t.id = f.tent_id
		LEFT JOIN bookings b ON b.tent_id = t.id
		WHERE f.phone = $1
		GROUP BY t.id
		-- MAX(), not a bare f.created_at: GROUP BY t.id functionally
		-- determines the tents columns, but favourites columns still
		-- have to be aggregated. There is one favourites row per
		-- (phone, tent) so MAX is just "that row's" timestamp.
		ORDER BY MAX(f.created_at) DESC
	`, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch favourites"})
		return
	}
	defer rows.Close()

	type fav struct {
		ID        int     `json:"id"`
		Name      string  `json:"name"`
		Class     string  `json:"class"`
		Price     int     `json:"price"`
		Location  string  `json:"location"`
		Rating    float64 `json:"rating"`
		Reviews   int     `json:"reviews"`
		Capacity  int     `json:"capacity"`
		Available int     `json:"available"`
	}
	out := []fav{}
	for rows.Next() {
		var f fav
		if rows.Scan(&f.ID, &f.Name, &f.Class, &f.Price, &f.Location,
			&f.Rating, &f.Reviews, &f.Capacity, &f.Available) == nil {
			out = append(out, f)
		}
	}
	c.JSON(http.StatusOK, gin.H{"favourites": out, "total": len(out)})
}

// POST /favourites  {phone, tent_id}
func addFavourite(c *gin.Context) {
	var body struct {
		Phone  string `json:"phone" binding:"required"`
		TentID int    `json:"tent_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Idempotent: tapping the heart twice from two devices must not
	// 500 on the unique constraint.
	_, err := db.Exec(`
		INSERT INTO favourites (phone, tent_id) VALUES ($1,$2)
		ON CONFLICT (phone, tent_id) DO NOTHING
	`, strings.TrimSpace(body.Phone), body.TentID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add favourite: " + err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"message": "Added to favourites", "tent_id": body.TentID})
}

// DELETE /favourites/:tentId?phone=
func removeFavourite(c *gin.Context) {
	phone := strings.TrimSpace(c.Query("phone"))
	tentID, err := strconv.Atoi(c.Param("tentId"))
	if phone == "" || err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone and a numeric tent id are required"})
		return
	}
	db.Exec(`DELETE FROM favourites WHERE phone = $1 AND tent_id = $2`, phone, tentID)
	c.JSON(http.StatusOK, gin.H{"message": "Removed from favourites", "tent_id": tentID})
}

// ── Snan calendar + reminders ────────────────────────────

// GET /snan-events?phone=
// phone is optional; when present each event carries whether this
// user has a reminder set, so the app can render the bell state in
// one round trip.
func listSnanEvents(c *gin.Context) {
	phone := strings.TrimSpace(c.Query("phone"))

	rows, err := db.Query(`
		SELECT e.event_date::text, e.name, COALESCE(e.significance,''),
		       COALESCE(e.location,''), e.is_amrit, COALESCE(e.surge,''),
		       CASE WHEN $1 <> '' AND r.id IS NOT NULL THEN TRUE ELSE FALSE END AS reminder_set
		FROM snan_events e
		LEFT JOIN snan_reminders r ON r.event_date = e.event_date AND r.phone = $1
		ORDER BY e.event_date
	`, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch snan events"})
		return
	}
	defer rows.Close()

	type ev struct {
		Date         string `json:"date"`
		Name         string `json:"name"`
		Significance string `json:"significance"`
		Location     string `json:"location"`
		IsAmrit      bool   `json:"is_amrit"`
		Surge        string `json:"surge,omitempty"`
		ReminderSet  bool   `json:"reminder_set"`
	}
	out := []ev{}
	for rows.Next() {
		var e ev
		if rows.Scan(&e.Date, &e.Name, &e.Significance, &e.Location,
			&e.IsAmrit, &e.Surge, &e.ReminderSet) == nil {
			out = append(out, e)
		}
	}
	c.JSON(http.StatusOK, gin.H{"events": out, "total": len(out)})
}

// POST /snan-reminders  {phone, date}
func addSnanReminder(c *gin.Context) {
	var body struct {
		Phone string `json:"phone" binding:"required"`
		Date  string `json:"date" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// The FK to snan_events rejects a date that is not a real Snan,
	// so a typo cannot create a reminder that never fires.
	_, err := db.Exec(`
		INSERT INTO snan_reminders (phone, event_date) VALUES ($1,$2::date)
		ON CONFLICT (phone, event_date) DO NOTHING
	`, strings.TrimSpace(body.Phone), body.Date)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not set reminder (is that a valid snan date?): " + err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"message": "Reminder set", "date": body.Date})
}

// DELETE /snan-reminders/:date?phone=
func removeSnanReminder(c *gin.Context) {
	phone := strings.TrimSpace(c.Query("phone"))
	date := c.Param("date")
	if phone == "" || date == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone and date are required"})
		return
	}
	db.Exec(`DELETE FROM snan_reminders WHERE phone = $1 AND event_date = $2::date`, phone, date)
	c.JSON(http.StatusOK, gin.H{"message": "Reminder removed", "date": date})
}

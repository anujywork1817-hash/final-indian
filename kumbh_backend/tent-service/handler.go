package main

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

type Tent struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Class        string   `json:"class"`
	Location     string   `json:"location"`
	Distance     float64  `json:"distance"`
	Rating       float64  `json:"rating"`
	Reviews      int      `json:"reviews"`
	Price        int      `json:"price"`
	BasePrice    int      `json:"base_price"`
	IsSurge      bool     `json:"is_surge"`
	Surge        string   `json:"surge"`
	Amenities    []string `json:"amenities"`
	Images       []string `json:"images"`
	Capacity     int      `json:"capacity"`
	TotalUnits   int      `json:"total_units"`
	Booked       int      `json:"booked"`
	Available    int      `json:"available"`
	Availability string   `json:"availability"` // "available", "limited", "almost_full", "sold_out"

	// ── Cancellation policy ──────────────────────────────
	// See kumbh_backend/migrations/002_cancellation_policy.sql.
	// The actual refund math never happens client-side — this is
	// display-only, for the policy badge on the tent/booking
	// screens.
	CancellationPolicyType      string  `json:"cancellation_policy_type"`
	FreeCancellationHours       int     `json:"free_cancellation_hours"`
	PartialRefundPenaltyPercent float64 `json:"partial_refund_penalty_percent"`
	LateCancellationHours       int     `json:"late_cancellation_hours"`
	NoShowCutoffHours           int     `json:"no_show_cutoff_hours"`
	NoShowPenaltyPercent        float64 `json:"no_show_penalty_percent"`
}

func getAvailabilityLabel(available, totalUnits int) string {
	// BUG-06: a tent with total_units = 0 (not yet configured) used to
	// divide by zero below and produce NaN/±Inf.
	if totalUnits <= 0 {
		return "unavailable"
	}
	if available <= 0 {
		return "sold_out"
	}
	pct := float64(available) / float64(totalUnits) * 100
	if pct <= 10 {
		return "almost_full"
	}
	if pct <= 50 {
		return "limited"
	}
	return "available"
}

func listTents(c *gin.Context) {
	class := c.Query("class")

	// available/booked here are TODAY's snapshot only (a coarse
	// "is this tent worth tapping into right now" signal for the
	// browse grid) — was comparing against t.capacity (guests per
	// tent, e.g. 2-4) and counting every booking ever made, so a
	// tent with as few as 2 bookings in its whole history looked
	// permanently sold out regardless of date or how many physical
	// units it actually has. Fixed to compare against total_units
	// (the real unit count) and only count bookings that haven't
	// checked out yet. The real per-date, per-unit check used at
	// booking time is booking-service's dailyAvailability — this is
	// just the list-page badge.
	query := `
		SELECT t.id, t.name, t.class, t.location, t.distance, t.rating, t.reviews,
		       t.price, t.base_price, t.is_surge, t.surge, t.amenities, t.images,
		       t.capacity, t.total_units,
		       COALESCE(SUM(b.units), 0) as booked,
		       t.total_units - COALESCE(SUM(b.units), 0) as available,
		       t.cancellation_policy_type, t.free_cancellation_hours,
		       t.partial_refund_penalty_percent, t.late_cancellation_hours,
		       t.no_show_cutoff_hours, t.no_show_penalty_percent
		FROM tents t
		LEFT JOIN bookings b ON b.tent_id = t.id
		  AND b.status IN ('confirmed', 'pending')
		  AND b.check_in <= CURRENT_DATE AND b.check_out > CURRENT_DATE
		WHERE t.is_active = TRUE
	`
	args := []interface{}{}

	if class != "" && class != "all" {
		query += " AND t.class = $1"
		args = append(args, class)
	}
	query += " GROUP BY t.id ORDER BY t.rating DESC"

	rows, err := db.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch tents"})
		return
	}
	defer rows.Close()

	var tents []Tent
	for rows.Next() {
		var t Tent
		err := rows.Scan(
			&t.ID, &t.Name, &t.Class, &t.Location,
			&t.Distance, &t.Rating, &t.Reviews,
			&t.Price, &t.BasePrice, &t.IsSurge, &t.Surge,
			pq.Array(&t.Amenities),
			pq.Array(&t.Images),
			&t.Capacity,
			&t.TotalUnits,
			&t.Booked,
			&t.Available,
			&t.CancellationPolicyType, &t.FreeCancellationHours,
			&t.PartialRefundPenaltyPercent, &t.LateCancellationHours,
			&t.NoShowCutoffHours, &t.NoShowPenaltyPercent,
		)
		if err != nil {
			continue
		}
		t.Availability = getAvailabilityLabel(t.Available, t.TotalUnits)
		tents = append(tents, t)
	}

	if tents == nil {
		tents = []Tent{}
	}

	c.JSON(http.StatusOK, gin.H{
		"tents": tents,
		"total": len(tents),
	})
}

func getTent(c *gin.Context) {
	id := c.Param("id")

	var t Tent
	err := db.QueryRow(`
		SELECT t.id, t.name, t.class, t.location, t.distance, t.rating, t.reviews,
		       t.price, t.base_price, t.is_surge, t.surge, t.amenities, t.images,
		       t.capacity, t.total_units,
		       COALESCE(SUM(b.units), 0) as booked,
		       t.total_units - COALESCE(SUM(b.units), 0) as available,
		       t.cancellation_policy_type, t.free_cancellation_hours,
		       t.partial_refund_penalty_percent, t.late_cancellation_hours,
		       t.no_show_cutoff_hours, t.no_show_penalty_percent
		FROM tents t
		LEFT JOIN bookings b ON b.tent_id = t.id
		  AND b.status IN ('confirmed', 'pending')
		  AND b.check_in <= CURRENT_DATE AND b.check_out > CURRENT_DATE
		WHERE t.id = $1 AND t.is_active = TRUE
		GROUP BY t.id
	`, id).Scan(
		&t.ID, &t.Name, &t.Class, &t.Location,
		&t.Distance, &t.Rating, &t.Reviews,
		&t.Price, &t.BasePrice, &t.IsSurge, &t.Surge,
		pq.Array(&t.Amenities),
		pq.Array(&t.Images),
		&t.Capacity,
		&t.TotalUnits,
		&t.Booked,
		&t.Available,
		&t.CancellationPolicyType, &t.FreeCancellationHours,
		&t.PartialRefundPenaltyPercent, &t.LateCancellationHours,
		&t.NoShowCutoffHours, &t.NoShowPenaltyPercent,
	)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "tent not found"})
		return
	}

	t.Availability = getAvailabilityLabel(t.Available, t.TotalUnits)
	c.JSON(http.StatusOK, t)
}

// GET /admin/tents — all tents including inactive
func adminGetTents(c *gin.Context) {
	rows, err := db.Query(`
		SELECT id, name, COALESCE(class,'standard'), price, base_price,
		       COALESCE(location,''), rating, reviews, is_active, total_units,
		       COALESCE(amenities::text, '[]'), capacity
		FROM tents ORDER BY id
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch tents"})
		return
	}
	defer rows.Close()

	type AdminTent struct {
		ID         int     `json:"id"`
		Name       string  `json:"name"`
		Class      string  `json:"class"`
		Price      int     `json:"price"`
		BasePrice  int     `json:"base_price"`
		Location   string  `json:"location"`
		Rating     float64 `json:"rating"`
		Reviews    int     `json:"reviews"`
		IsActive   bool    `json:"is_active"`
		TotalUnits int     `json:"total_units"`
		Amenities  string  `json:"amenities"`
		Capacity   int     `json:"capacity"`
	}

	var tents []AdminTent
	for rows.Next() {
		var t AdminTent
		rows.Scan(&t.ID, &t.Name, &t.Class, &t.Price, &t.BasePrice,
			&t.Location, &t.Rating, &t.Reviews, &t.IsActive, &t.TotalUnits,
			&t.Amenities, &t.Capacity)
		tents = append(tents, t)
	}
	if tents == nil {
		tents = []AdminTent{}
	}
	c.JSON(http.StatusOK, gin.H{"tents": tents})
}

// PUT /admin/tents/:id — update tent
func adminUpdateTent(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Name       string `json:"name"`
		Price      int    `json:"price"`
		BasePrice  int    `json:"base_price"`
		Location   string `json:"location"`
		TotalUnits int    `json:"total_units"`
		Class      string `json:"class"`
		IsActive   *bool  `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := db.Exec(`
		UPDATE tents SET
			name = COALESCE(NULLIF($1,''), name),
			price = CASE WHEN $2 > 0 THEN $2 ELSE price END,
			base_price = CASE WHEN $3 > 0 THEN $3 ELSE base_price END,
			location = COALESCE(NULLIF($4,''), location),
			total_units = CASE WHEN $5 > 0 THEN $5 ELSE total_units END,
			class = COALESCE(NULLIF($6,''), class),
			is_active = COALESCE($7, is_active)
		WHERE id = $8
	`, req.Name, req.Price, req.BasePrice, req.Location, req.TotalUnits, req.Class, req.IsActive, id)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update tent: " + err.Error()})
		return
	}
	logAdminAction(adminUsernameFromToken(c), "TENT_UPDATED", "tent", id, "")
	c.JSON(http.StatusOK, gin.H{"message": "Tent updated successfully"})
}

// POST /admin/tents — create new tent
func adminCreateTent(c *gin.Context) {
	var req struct {
		Name       string `json:"name" binding:"required"`
		Class      string `json:"class"`
		Price      int    `json:"price" binding:"required"`
		Location   string `json:"location"`
		TotalUnits int    `json:"total_units"`
		Capacity   int    `json:"capacity"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Class == "" {
		req.Class = "standard"
	}
	if req.TotalUnits == 0 {
		req.TotalUnits = 33
	}
	if req.Capacity == 0 {
		req.Capacity = 2
	}

	var id int
	err := db.QueryRow(`
		INSERT INTO tents (name, class, price, base_price, location, total_units, capacity, is_active, rating, reviews)
		VALUES ($1, $2, $3, $3, $4, $5, $6, true, 0, 0) RETURNING id
	`, req.Name, req.Class, req.Price, req.Location, req.TotalUnits, req.Capacity).Scan(&id)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create tent: " + err.Error()})
		return
	}
	logAdminAction(adminUsernameFromToken(c), "TENT_CREATED", "tent", fmt.Sprint(id), "")
	c.JSON(http.StatusCreated, gin.H{"message": "Tent created successfully", "id": id})
}

// DELETE /admin/tents/:id — delete tent
func adminDeleteTent(c *gin.Context) {
	id := c.Param("id")
	_, err := db.Exec(`DELETE FROM tents WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete tent"})
		return
	}
	logAdminAction(adminUsernameFromToken(c), "TENT_DELETED", "tent", id, "")
	c.JSON(http.StatusOK, gin.H{"message": "Tent deleted successfully"})
}

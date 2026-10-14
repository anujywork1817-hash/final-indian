package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type Booking struct {
	ID          int       `json:"id"`
	BookingRef  string    `json:"booking_ref"`
	Phone       string    `json:"phone"`
	TentID      int       `json:"tent_id"`
	TentName    string    `json:"tent_name"`
	Location    string    `json:"location"`
	Class       string    `json:"class"`
	CheckIn     string    `json:"check_in"`
	CheckOut    string    `json:"check_out"`
	Nights      int       `json:"nights"`
	Guests      int       `json:"guests"`
	Units       int       `json:"units"`
	BaseAmount  float64   `json:"base_amount"`
	CouponCode  string    `json:"coupon_code,omitempty"`
	Discount    float64   `json:"discount"`
	Tax         float64   `json:"tax"`
	TotalAmount float64   `json:"total_amount"`
	Status      string    `json:"status"`
	PaymentID   string    `json:"payment_id,omitempty"`
	GuestName   string    `json:"guest_name,omitempty"`
	GuestPhone  string    `json:"guest_phone,omitempty"`
	IDProof     string    `json:"id_proof,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	Images      []string  `json:"images"`
}

func createBooking(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		TentID     int                    `json:"tent_id" binding:"required"`
		CheckIn    string                 `json:"check_in" binding:"required"`
		CheckOut   string                 `json:"check_out" binding:"required"`
		Guests     int                    `json:"guests"`
		Units      int                    `json:"units"`
		CouponCode string                 `json:"coupon_code"`
		Addons     map[string]interface{} `json:"addons"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Guests == 0 {
		req.Guests = 1
	}
	if req.Units == 0 {
		req.Units = 1
	}

	guestName := ""
	guestPhone := ""
	idProof := ""
	bedType := "Single"
	genderPref := "Mixed"

	if req.Addons != nil {
		if v, ok := req.Addons["guest_name"].(string); ok {
			guestName = v
		}
		if v, ok := req.Addons["guest_phone"].(string); ok {
			guestPhone = v
		}
		if v, ok := req.Addons["id_proof"].(string); ok {
			idProof = v
		}
		if v, ok := req.Addons["bed_type"].(string); ok {
			bedType = v
		}
		if v, ok := req.Addons["gender_preference"].(string); ok {
			genderPref = v
		}
	}

	addonsJSON, _ := json.Marshal(req.Addons)

	// ── BEGIN TRANSACTION with lock ───────────────────────────
	tx, err := db.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback()

	// ── Step 1: Lock tent row + get total_units ───────────────
	// FOR UPDATE locks this row — other requests wait here
	var tentName, location, class string
	var pricePerNight, totalUnits int
	err = tx.QueryRow(`
		SELECT name, price, location, class, total_units
		FROM tents
		WHERE id = $1 AND is_active = TRUE
		FOR UPDATE
	`, req.TentID).Scan(&tentName, &pricePerNight, &location, &class, &totalUnits)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "tent not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch tent"})
		}
		return
	}

	// ── Step 2: Count already booked units for these dates ────
	// Safe — no other request can slip in between (lock held)
	var bookedUnits int
	err = tx.QueryRow(`
		SELECT COALESCE(SUM(units), 0) FROM bookings
		WHERE tent_id = $1
		AND status NOT IN ('cancelled')
		AND check_in < $3::date
		AND check_out > $2::date
	`, req.TentID, req.CheckIn, req.CheckOut).Scan(&bookedUnits)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "availability check failed"})
		return
	}

	// ── Step 3: Check if enough units available ───────────────
	remainingUnits := totalUnits - bookedUnits
	if remainingUnits <= 0 {
		c.JSON(http.StatusConflict, gin.H{
			"error":           "All tents are fully booked for selected dates. Please choose different dates.",
			"total_units":     totalUnits,
			"booked_units":    bookedUnits,
			"remaining_units": 0,
		})
		return
	}
	if req.Units > remainingUnits {
		c.JSON(http.StatusConflict, gin.H{
			"error":           fmt.Sprintf("Only %d tent(s) available for selected dates.", remainingUnits),
			"total_units":     totalUnits,
			"booked_units":    bookedUnits,
			"remaining_units": remainingUnits,
		})
		return
	}

	// ── Step 4: Calculate dates and amounts ───────────────────
	checkIn, _ := time.Parse("2006-01-02", req.CheckIn)
	checkOut, _ := time.Parse("2006-01-02", req.CheckOut)
	nights := int(checkOut.Sub(checkIn).Hours() / 24)
	if nights < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid dates"})
		return
	}

	baseAmount := float64(pricePerNight * nights * req.Units)
	discount := 0.0
	couponCode := ""

	// ── Step 5: Validate coupon ───────────────────────────────
	if req.CouponCode != "" {
		var discountRate float64
		var minAmount int
		var usedCount, maxUses int
		var isActive bool
		var expiresAt time.Time

		err := tx.QueryRow(`
			SELECT discount, min_amount, used_count, max_uses, is_active, expires_at
			FROM coupons WHERE code = $1
		`, req.CouponCode).Scan(&discountRate, &minAmount, &usedCount, &maxUses, &isActive, &expiresAt)

		if err == nil && isActive &&
			usedCount < maxUses &&
			time.Now().Before(expiresAt) &&
			baseAmount >= float64(minAmount) {
			discount = baseAmount * discountRate
			couponCode = req.CouponCode
			tx.Exec("UPDATE coupons SET used_count = used_count + 1 WHERE code = $1", req.CouponCode)
		}
	}

	tax := (baseAmount - discount) * 0.12
	totalAmount := baseAmount - discount + tax

	// ── Step 6: Generate unique booking ref ───────────────────
	ref := fmt.Sprintf("KTB-2027-%05d", rand.Intn(99999))

	// ── Step 7: Insert booking ────────────────────────────────
	var bookingID int
	err = tx.QueryRow(`
		INSERT INTO bookings
			(booking_ref, phone, tent_id, tent_name, location, class,
			 check_in, check_out, nights, guests, units,
			 base_amount, coupon_code, discount, tax, total_amount, status,
			 guest_name, guest_phone, id_proof, bed_type, gender_preference, addons)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'pending',$17,$18,$19,$20,$21,$22)
		RETURNING id
	`, ref, phone, req.TentID, tentName, location, class,
		req.CheckIn, req.CheckOut,
		nights, req.Guests, req.Units,
		baseAmount, couponCode, discount, tax, totalAmount,
		guestName, guestPhone, idProof, bedType, genderPref, string(addonsJSON),
	).Scan(&bookingID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create booking: " + err.Error()})
		return
	}

	// ── Step 8: Commit — releases the lock ────────────────────
	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to confirm booking"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"booking": gin.H{
			"id":              bookingID,
			"booking_ref":     ref,
			"tent_name":       tentName,
			"location":        location,
			"class":           class,
			"check_in":        req.CheckIn,
			"check_out":       req.CheckOut,
			"nights":          nights,
			"guests":          req.Guests,
			"units":           req.Units,
			"base_amount":     baseAmount,
			"coupon_code":     couponCode,
			"discount":        discount,
			"tax":             tax,
			"total_amount":    totalAmount,
			"status":          "pending",
			"remaining_units": remainingUnits - req.Units,
		},
		"message": "Booking created! Complete payment to confirm.",
	})
}

func myBookings(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	rows, err := db.Query(`
		SELECT b.id, b.booking_ref, b.phone, b.tent_id, b.tent_name,
		       COALESCE(b.location,''), COALESCE(b.class,''),
		       b.check_in, b.check_out, b.nights, b.guests, b.units,
		       b.base_amount, COALESCE(b.coupon_code,''), b.discount, b.tax,
		       b.total_amount, b.status, COALESCE(b.payment_id,''),
		       COALESCE(b.guest_name,''), COALESCE(b.guest_phone,''), COALESCE(b.id_proof,''),
		       b.created_at,
		       COALESCE(t.images::text, '[]')
		FROM bookings b
		LEFT JOIN tents t ON t.id = b.tent_id
		WHERE b.phone = $1
		ORDER BY b.created_at DESC
	`, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	defer rows.Close()

	var bookings []Booking
	for rows.Next() {
		var b Booking
		var imagesStr string
		rows.Scan(
			&b.ID, &b.BookingRef, &b.Phone, &b.TentID, &b.TentName,
			&b.Location, &b.Class,
			&b.CheckIn, &b.CheckOut, &b.Nights, &b.Guests, &b.Units,
			&b.BaseAmount, &b.CouponCode, &b.Discount, &b.Tax,
			&b.TotalAmount, &b.Status, &b.PaymentID,
			&b.GuestName, &b.GuestPhone, &b.IDProof,
			&b.CreatedAt, &imagesStr,
		)
		json.Unmarshal([]byte(imagesStr), &b.Images)
		if b.Images == nil {
			b.Images = []string{}
		}
		bookings = append(bookings, b)
	}

	if bookings == nil {
		bookings = []Booking{}
	}

	c.JSON(http.StatusOK, gin.H{
		"bookings": bookings,
		"total":    len(bookings),
	})
}

func cancelBooking(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	ref := c.Param("ref")

	var status string
	err := db.QueryRow(`
		SELECT status FROM bookings WHERE booking_ref = $1 AND phone = $2
	`, ref, phone).Scan(&status)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	if status == "cancelled" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "booking already cancelled"})
		return
	}
	if status == "completed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "completed booking cannot be cancelled"})
		return
	}

	_, err = db.Exec(`
		UPDATE bookings SET status = 'cancelled', updated_at = NOW()
		WHERE booking_ref = $1 AND phone = $2
	`, ref, phone)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to cancel booking"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Booking cancelled successfully",
		"booking_ref": ref,
		"status":      "cancelled",
	})
}

func validateCoupon(c *gin.Context) {
	var req struct {
		Code   string  `json:"code" binding:"required"`
		Amount float64 `json:"amount"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var discount float64
	var description string
	var minAmount int
	var usedCount, maxUses int
	var isActive bool
	var expiresAt time.Time

	err := db.QueryRow(`
		SELECT discount, description, min_amount, used_count, max_uses, is_active, expires_at
		FROM coupons WHERE code = $1
	`, req.Code).Scan(&discount, &description, &minAmount, &usedCount, &maxUses, &isActive, &expiresAt)

	if err != nil {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Invalid coupon code"})
		return
	}
	if !isActive {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Coupon is inactive"})
		return
	}
	if usedCount >= maxUses {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Coupon usage limit reached"})
		return
	}
	if time.Now().After(expiresAt) {
		c.JSON(http.StatusOK, gin.H{"valid": false, "message": "Coupon has expired"})
		return
	}
	if req.Amount > 0 && req.Amount < float64(minAmount) {
		c.JSON(http.StatusOK, gin.H{
			"valid":   false,
			"message": fmt.Sprintf("Minimum booking amount ₹%d required", minAmount),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"valid":       true,
		"discount":    discount,
		"description": description,
		"message":     fmt.Sprintf("%.0f%% discount applied! %s", discount*100, description),
	})
}

func listCoupons(c *gin.Context) {
	rows, err := db.Query(`
		SELECT code, description, discount, min_amount, max_uses, used_count, expires_at
		FROM coupons WHERE is_active = TRUE AND expires_at > NOW()
		ORDER BY discount DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch coupons"})
		return
	}
	defer rows.Close()

	type Coupon struct {
		Code        string    `json:"code"`
		Description string    `json:"description"`
		Discount    float64   `json:"discount"`
		MinAmount   int       `json:"min_amount"`
		MaxUses     int       `json:"max_uses"`
		UsedCount   int       `json:"used_count"`
		ExpiresAt   time.Time `json:"expires_at"`
	}

	var coupons []Coupon
	for rows.Next() {
		var cp Coupon
		rows.Scan(&cp.Code, &cp.Description, &cp.Discount,
			&cp.MinAmount, &cp.MaxUses, &cp.UsedCount, &cp.ExpiresAt)
		coupons = append(coupons, cp)
	}
	if coupons == nil {
		coupons = []Coupon{}
	}
	c.JSON(http.StatusOK, gin.H{"coupons": coupons})
}
func deleteBooking(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	ref := c.Param("ref")

	// Only allow deleting cancelled bookings
	var status string
	err := db.QueryRow(`
		SELECT status FROM bookings WHERE booking_ref = $1 AND phone = $2
	`, ref, phone).Scan(&status)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	if status != "cancelled" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "only cancelled bookings can be deleted"})
		return
	}

	_, err = db.Exec(`
		DELETE FROM payments WHERE booking_ref = $1
	`, ref)

	_, err = db.Exec(`
		DELETE FROM bookings WHERE booking_ref = $1 AND phone = $2
	`, ref, phone)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete booking"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Booking deleted successfully",
		"booking_ref": ref,
	})
}

// ── Admin Routes ─────────────────────────────────────────────────

// GET /admin/bookings — all bookings
func adminGetBookings(c *gin.Context) {
	rows, err := db.Query(`
		SELECT b.id, b.booking_ref, b.phone, b.tent_id, b.tent_name,
		       COALESCE(b.location,''), COALESCE(b.class,''),
		       b.check_in, b.check_out, b.nights, b.guests, b.units,
		       b.base_amount, COALESCE(b.coupon_code,''), b.discount, b.tax,
		       b.total_amount, b.status, COALESCE(b.payment_id,''),
		       COALESCE(b.guest_name,''), COALESCE(b.guest_phone,''), COALESCE(b.id_proof,''),
		       b.created_at
		FROM bookings b
		ORDER BY b.created_at DESC
		LIMIT 100
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	defer rows.Close()

	var bookings []Booking
	for rows.Next() {
		var b Booking
		rows.Scan(
			&b.ID, &b.BookingRef, &b.Phone, &b.TentID, &b.TentName,
			&b.Location, &b.Class,
			&b.CheckIn, &b.CheckOut, &b.Nights, &b.Guests, &b.Units,
			&b.BaseAmount, &b.CouponCode, &b.Discount, &b.Tax,
			&b.TotalAmount, &b.Status, &b.PaymentID,
			&b.GuestName, &b.GuestPhone, &b.IDProof,
			&b.CreatedAt,
		)
		b.Images = []string{}
		bookings = append(bookings, b)
	}
	if bookings == nil {
		bookings = []Booking{}
	}
	c.JSON(http.StatusOK, gin.H{"bookings": bookings, "total": len(bookings)})
}

// PUT /admin/bookings/:ref/status — update booking status
func adminUpdateBookingStatus(c *gin.Context) {
	ref := c.Param("ref")
	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	validStatuses := map[string]bool{"confirmed": true, "pending": true, "checked_in": true, "completed": true, "cancelled": true}
	if !validStatuses[req.Status] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status"})
		return
	}

	_, err := db.Exec(`UPDATE bookings SET status = $1 WHERE booking_ref = $2`, req.Status, ref)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update status"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Status updated", "booking_ref": ref, "status": req.Status})
}

// GET /admin/stats — dashboard stats
func adminGetStats(c *gin.Context) {
	var totalBookings, activeBookings, totalUsers, newUsersToday int
	var totalRevenue, todayRevenue float64

	db.QueryRow(`SELECT COUNT(*) FROM bookings`).Scan(&totalBookings)
	db.QueryRow(`SELECT COUNT(*) FROM bookings WHERE status IN ('confirmed','checked_in')`).Scan(&activeBookings)
	db.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status != 'cancelled'`).Scan(&totalRevenue)
	db.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status != 'cancelled' AND DATE(created_at) = CURRENT_DATE`).Scan(&todayRevenue)

	c.JSON(http.StatusOK, gin.H{
		"total_bookings":  totalBookings,
		"active_bookings": activeBookings,
		"total_revenue":   totalRevenue,
		"today_revenue":   todayRevenue,
		"total_users":     totalUsers,
		"new_users_today": newUsersToday,
	})
}

// GET /admin/revenue/weekly — last 7 days revenue
func adminWeeklyRevenue(c *gin.Context) {
	rows, err := db.Query(`
		SELECT TO_CHAR(DATE(created_at), 'Dy') as day,
		       COALESCE(SUM(total_amount), 0) as amount
		FROM bookings
		WHERE status != 'cancelled'
		  AND created_at >= NOW() - INTERVAL '7 days'
		GROUP BY DATE(created_at), TO_CHAR(DATE(created_at), 'Dy')
		ORDER BY DATE(created_at)
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch revenue"})
		return
	}
	defer rows.Close()

	type DayRevenue struct {
		Day    string  `json:"day"`
		Amount float64 `json:"amount"`
	}
	var revenue []DayRevenue
	for rows.Next() {
		var r DayRevenue
		rows.Scan(&r.Day, &r.Amount)
		revenue = append(revenue, r)
	}
	if revenue == nil {
		revenue = []DayRevenue{}
	}
	c.JSON(http.StatusOK, gin.H{"revenue": revenue})
}


// GET /admin/coupons — all coupons
func adminGetCoupons(c *gin.Context) {
	rows, err := db.Query(`
		SELECT id, code, COALESCE(description,''), discount, min_amount,
		       max_uses, used_count, is_active, expires_at
		FROM coupons ORDER BY created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch coupons"})
		return
	}
	defer rows.Close()

	type AdminCoupon struct {
		ID          int       `json:"id"`
		Code        string    `json:"code"`
		Description string    `json:"description"`
		Discount    float64   `json:"discount"`
		MinAmount   int       `json:"min_amount"`
		MaxUses     int       `json:"max_uses"`
		UsedCount   int       `json:"used_count"`
		IsActive    bool      `json:"is_active"`
		ExpiresAt   time.Time `json:"expires_at"`
	}

	var coupons []AdminCoupon
	for rows.Next() {
		var cp AdminCoupon
		rows.Scan(&cp.ID, &cp.Code, &cp.Description, &cp.Discount,
			&cp.MinAmount, &cp.MaxUses, &cp.UsedCount, &cp.IsActive, &cp.ExpiresAt)
		coupons = append(coupons, cp)
	}
	if coupons == nil {
		coupons = []AdminCoupon{}
	}
	c.JSON(http.StatusOK, gin.H{"coupons": coupons})
}

// POST /admin/coupons — create coupon
func adminCreateCoupon(c *gin.Context) {
	var req struct {
		Code        string  `json:"code" binding:"required"`
		Description string  `json:"description"`
		Discount    float64 `json:"discount" binding:"required"`
		MinAmount   int     `json:"min_amount"`
		MaxUses     int     `json:"max_uses"`
		ExpiresAt   string  `json:"expires_at" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.MaxUses == 0 { req.MaxUses = 100 }

	_, err := db.Exec(`
		INSERT INTO coupons (code, description, discount, min_amount, max_uses, used_count, is_active, expires_at)
		VALUES ($1, $2, $3, $4, $5, 0, true, $6)
	`, req.Code, req.Description, req.Discount, req.MinAmount, req.MaxUses, req.ExpiresAt)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create coupon: " + err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"message": "Coupon created successfully"})
}

// PUT /admin/coupons/:id/toggle — toggle active status
func adminToggleCoupon(c *gin.Context) {
	id := c.Param("id")
	_, err := db.Exec(`UPDATE coupons SET is_active = NOT is_active WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to toggle coupon"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Coupon status toggled"})
}

// DELETE /admin/coupons/:id — delete coupon
func adminDeleteCoupon(c *gin.Context) {
	id := c.Param("id")
	_, err := db.Exec(`DELETE FROM coupons WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete coupon"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Coupon deleted"})
}
// POST /admin/notifications/send — broadcast notification to users
func adminSendNotification(c *gin.Context) {
	var req struct {
		Title  string `json:"title" binding:"required"`
		Body   string `json:"body" binding:"required"`
		Target string `json:"target"` // "all", "active", "new"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Target == "" {
		req.Target = "all"
	}

	// Build query based on target
	var query string
	switch req.Target {
	case "active":
		query = `SELECT DISTINCT u.fcm_token FROM users u
			JOIN bookings b ON b.phone = u.phone
			WHERE u.fcm_token IS NOT NULL AND u.fcm_token != ''
			AND b.status IN ('confirmed', 'pending')`
	case "new":
		query = `SELECT fcm_token FROM users
			WHERE fcm_token IS NOT NULL AND fcm_token != ''
			AND created_at >= NOW() - INTERVAL '7 days'`
	default: // all
		query = `SELECT fcm_token FROM users
			WHERE fcm_token IS NOT NULL AND fcm_token != ''`
	}

	rows, err := db.Query(query)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch users"})
		return
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		rows.Scan(&token)
		if token != "" {
			tokens = append(tokens, token)
		}
	}

	// Send notifications in background
	sent := 0
	for _, token := range tokens {
		go sendFCMNotification(token, req.Title, req.Body)
		sent++
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("Notification sent to %d users", sent),
		"sent":    sent,
		"target":  req.Target,
	})
}

// DELETE /admin/bookings/cancelled — clear cancelled bookings older than 30 days
func adminClearCancelledBookings(c *gin.Context) {
	result, err := db.Exec(`
		DELETE FROM bookings 
		WHERE status = 'cancelled' 
		AND updated_at < NOW() - INTERVAL '30 days'
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to clear bookings"})
		return
	}
	rows, _ := result.RowsAffected()
	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Cleared %d cancelled bookings", rows), "deleted": rows})
}
func adminClearAllCancelledBookings(c *gin.Context) {
	result, err := db.Exec(`DELETE FROM bookings WHERE status = 'cancelled'`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to clear bookings"})
		return
	}
	rows, _ := result.RowsAffected()
	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Cleared %d cancelled bookings", rows), "deleted": rows})
}
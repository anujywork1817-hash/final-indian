package main

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type Review struct {
	ID         int       `json:"id"`
	BookingRef string    `json:"booking_ref"`
	TentID     int       `json:"tent_id"`
	Phone      string    `json:"phone"`
	Rating     int       `json:"rating"`
	Review     string    `json:"review"`
	CreatedAt  time.Time `json:"created_at"`
}

// POST /tents/:id/reviews
func submitReview(c *gin.Context) {
	phone := verifiedPhone(c)
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	tentIDStr := c.Param("id")
	tentID, err := strconv.Atoi(tentIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tent id"})
		return
	}

	var req struct {
		BookingRef string `json:"booking_ref" binding:"required"`
		Rating     int    `json:"rating" binding:"required"`
		Review     string `json:"review"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Rating < 1 || req.Rating > 5 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "rating must be between 1 and 5"})
		return
	}

	// Verify booking belongs to user and is confirmed
	var bookingStatus string
	err = db.QueryRow(`
		SELECT status FROM bookings 
		WHERE booking_ref = $1 AND phone = $2 AND tent_id = $3
	`, req.BookingRef, phone, tentID).Scan(&bookingStatus)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if bookingStatus != "confirmed" && bookingStatus != "completed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "can only review confirmed bookings"})
		return
	}

	// Insert review
	_, err = db.Exec(`
		INSERT INTO reviews (booking_ref, tent_id, phone, rating, review)
		VALUES ($1, $2, $3, $4, $5)
	`, req.BookingRef, tentID, phone, req.Rating, req.Review)
	if err != nil {
		// Check for duplicate review (unique constraint on booking_ref)
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "duplicate") {
			c.JSON(http.StatusConflict, gin.H{"error": "you have already reviewed this booking"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to submit review: " + err.Error()})
		return
	}

	// Update tent rating
	db.Exec(`
		UPDATE tents SET 
			rating = (SELECT AVG(rating) FROM reviews WHERE tent_id = $1),
			reviews = (SELECT COUNT(*) FROM reviews WHERE tent_id = $1)
		WHERE id = $1
	`, tentID)

	c.JSON(http.StatusCreated, gin.H{
		"message": "Review submitted successfully! 🙏",
		"rating":  req.Rating,
	})
}

// GET /tents/:id/reviews
func getReviews(c *gin.Context) {
	tentIDStr := c.Param("id")
	tentID, err := strconv.Atoi(tentIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tent id"})
		return
	}

	rows, err := db.Query(`
		SELECT r.id, r.booking_ref, r.tent_id, r.phone, r.rating, 
		       COALESCE(r.review, ''), r.created_at
		FROM reviews r
		WHERE r.tent_id = $1
		ORDER BY r.created_at DESC
		LIMIT 20
	`, tentID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch reviews"})
		return
	}
	defer rows.Close()

	var reviews []Review
	for rows.Next() {
		var rv Review
		rows.Scan(&rv.ID, &rv.BookingRef, &rv.TentID, &rv.Phone,
			&rv.Rating, &rv.Review, &rv.CreatedAt)
		// Mask phone number for privacy
		if len(rv.Phone) >= 5 {
			rv.Phone = rv.Phone[:5] + "XXXXX"
		}
		reviews = append(reviews, rv)
	}
	if reviews == nil {
		reviews = []Review{}
	}

	var avgRating float64
	var totalReviews int
	db.QueryRow(`
		SELECT COALESCE(AVG(rating), 0), COUNT(*)
		FROM reviews WHERE tent_id = $1
	`, tentID).Scan(&avgRating, &totalReviews)

	c.JSON(http.StatusOK, gin.H{
		"reviews":    reviews,
		"total":      totalReviews,
		"avg_rating": avgRating,
	})
}

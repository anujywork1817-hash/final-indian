package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

var db *sql.DB

func main() {
	godotenv.Load()

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://postgres:password@localhost:5432/kumbh_tent?sslmode=disable"
	}

	var err error
	db, err = sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("DB connection failed: %v", err)
	}
	defer db.Close()

	if err = db.Ping(); err != nil {
		log.Fatalf("DB not reachable: %v", err)
	}
	fmt.Println("✅ Booking Service — DB connected!")

	// ── Start daily reminder scheduler ────────────────────
	go startReminderScheduler()

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type,Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "booking-service"})
	})
	r.HEAD("/health", func(c *gin.Context) {
    c.Status(200)
    })

	r.POST("/bookings", createBooking)
	r.GET("/bookings", myBookings)
	r.PUT("/bookings/:ref/cancel", cancelBooking)
	r.DELETE("/bookings/:ref", deleteBooking)
	r.POST("/coupons/validate", validateCoupon)
	r.GET("/coupons", listCoupons)
	r.GET("/admin/bookings", adminGetBookings)
    r.PUT("/admin/bookings/:ref/status", adminUpdateBookingStatus)
    r.GET("/admin/stats", adminGetStats)
    r.GET("/admin/revenue/weekly", adminWeeklyRevenue)

	r.GET("/admin/coupons", adminGetCoupons)
    r.POST("/admin/coupons", adminCreateCoupon)
    r.PUT("/admin/coupons/:id/toggle", adminToggleCoupon)
    r.DELETE("/admin/coupons/:id", adminDeleteCoupon)
	r.POST("/admin/notifications/send", adminSendNotification)
	r.DELETE("/admin/bookings/cancelled", adminClearCancelledBookings)
	r.DELETE("/admin/bookings/cancelled/all", adminClearAllCancelledBookings)

	port := os.Getenv("BOOKING_SERVICE_PORT")
	if port == "" {
		port = "8083"
	}
	fmt.Printf("🚀 Booking Service running on :%s\n", port)
	r.Run(":" + port)
}

func startReminderScheduler() {
	for {
		now := time.Now().UTC()
		// 8 AM IST = 2:30 AM UTC
		next := time.Date(now.Year(), now.Month(), now.Day(), 2, 30, 0, 0, time.UTC)
		if now.After(next) {
			next = next.Add(24 * time.Hour)
		}
		waitDuration := time.Until(next)
		fmt.Printf("⏰ Next reminder run in: %s\n", waitDuration.Round(time.Minute))
		time.Sleep(waitDuration)
		sendBookingReminders()
	}
}

package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

var db *sql.DB

func main() {
	godotenv.Load()
	requireEnv("JWT_SECRET")

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
		log.Printf("Warning: DB not reachable: %v", err)
	} else {
		fmt.Println("✅ Database connected!")
	}

	r := gin.Default()

	r.Use(corsMiddleware())

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "app": "Kumbh Tent API"})
	})

	// Auth routes
	r.POST("/api/v1/auth/send-otp", sendOTP)
	r.POST("/api/v1/auth/verify-otp", verifyOTP)

	// Tent routes (public)
	r.GET("/api/v1/tents", listTents)
	r.GET("/api/v1/tents/:id", getTent)

	// Protected routes
	protected := r.Group("/api/v1")
	protected.Use(authMiddleware())
	{
		protected.POST("/bookings", createBooking)
		protected.GET("/bookings", myBookings)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}
	fmt.Printf("🚀 Server running on http://localhost:%s\n", port)
	r.Run(":" + port)
}

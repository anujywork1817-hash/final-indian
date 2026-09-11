package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

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
		log.Fatalf("DB not reachable: %v", err)
	}
	fmt.Println("✅ Tent Service — DB connected!")

	// Postgres on this box caps out well under 100 connections shared
	// across all 5 services; an unbounded pool here let one busy
	// service starve the others under load.
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetConnMaxIdleTime(2 * time.Minute)

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	r.Use(corsMiddleware())

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "tent-service"})
	})

	r.HEAD("/health", func(c *gin.Context) {
		c.Status(200)
	})

	r.GET("/tents", listTents)
	r.GET("/tents/:id", getTent)

	// ── Review routes ─────────────────────────────────────
	r.POST("/tents/:id/reviews", submitReview)
	r.GET("/tents/:id/reviews", getReviews)

	// BUG-15: every /admin/* route now requires its own valid admin
	// JWT (requireAdmin, audit.go), not just api-gateway's adminGuard.
	admin := r.Group("/admin")
	admin.Use(requireAdmin())
	admin.GET("/tents", adminGetTents)
	admin.POST("/tents", adminCreateTent)
	admin.PUT("/tents/:id", adminUpdateTent)
	admin.DELETE("/tents/:id", adminDeleteTent)

	port := os.Getenv("TENT_SERVICE_PORT")
	if port == "" {
		port = "8082"
	}
	fmt.Printf("🚀 Tent Service running on :%s\n", port)
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	log.Fatal(srv.ListenAndServe())
}

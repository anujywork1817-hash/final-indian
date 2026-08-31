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

	r.GET("/admin/tents", adminGetTents)
	r.POST("/admin/tents", adminCreateTent)
	r.PUT("/admin/tents/:id", adminUpdateTent)
	r.DELETE("/admin/tents/:id", adminDeleteTent)

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

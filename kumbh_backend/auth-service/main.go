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
	fmt.Println("✅ Auth Service — DB connected!")

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
		c.JSON(200, gin.H{"status": "ok", "service": "auth-service"})
	})
	r.HEAD("/health", func(c *gin.Context) {
		c.Status(200)
	})
	r.POST("/auth/send-otp", sendOTP)
	r.POST("/auth/verify-otp", verifyOTP)
	r.GET("/auth/profile", getProfile)
	r.PUT("/auth/profile", updateProfile)
	r.POST("/auth/fcm-token", updateFCMToken)
	r.POST("/auth/kyc", submitKYC)
	r.POST("/auth/admin/login", adminLogin)
	r.POST("/auth/admin/change-password", adminChangePassword)
	r.POST("/auth/admin/change-username", adminChangeUsername)
	r.GET("/auth/admin/list", requireSuperAdmin(), adminListAdmins)
	r.POST("/auth/admin/create", requireSuperAdmin(), adminCreateAdmin)
	// BUG-15: every /admin/* route now requires its own valid admin
	// JWT (requireAdmin, rbac.go), not just api-gateway's adminGuard.
	admin := r.Group("/admin")
	admin.Use(requireAdmin())
	admin.GET("/users", adminGetUsers)
	admin.PUT("/users/:phone/block", adminBlockUser)
	admin.GET("/kyc", adminGetKYC)
	admin.PUT("/kyc/:phone/verify", adminVerifyKYC)

	port := os.Getenv("AUTH_SERVICE_PORT")
	if port == "" {
		port = "8081"
	}
	fmt.Printf("🚀 Auth Service running on :%s\n", port)
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

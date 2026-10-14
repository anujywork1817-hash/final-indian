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
	r.GET("/admin/users", adminGetUsers)
    r.PUT("/admin/users/:phone/block", adminBlockUser)
	r.GET("/admin/kyc", adminGetKYC)
    r.PUT("/admin/kyc/:phone/verify", adminVerifyKYC)

	port := os.Getenv("AUTH_SERVICE_PORT")
	if port == "" {
		port = "8081"
	}
	fmt.Printf("🚀 Auth Service running on :%s\n", port)
	r.Run(":" + port)
}
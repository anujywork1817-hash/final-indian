package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/joho/godotenv"
)

func main() {
	godotenv.Load()

	authURL := os.Getenv("AUTH_SERVICE_URL")
	tentURL := os.Getenv("TENT_SERVICE_URL")
	bookingURL := os.Getenv("BOOKING_SERVICE_URL")
	paymentURL := os.Getenv("PAYMENT_SERVICE_URL")

	if authURL == "" {
		authURL = "http://localhost:8081"
	}
	if tentURL == "" {
		tentURL = "http://localhost:8082"
	}
	if bookingURL == "" {
		bookingURL = "http://localhost:8083"
	}
	if paymentURL == "" {
		paymentURL = "http://localhost:8084"
	}

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
		c.JSON(200, gin.H{
			"status":  "ok",
			"service": "api-gateway",
			"services": gin.H{
				"auth":    authURL,
				"tents":   tentURL,
				"booking": bookingURL,
				"payment": paymentURL,
			},
		})
	})
	r.HEAD("/health", func(c *gin.Context) {
    c.Status(200)
    })

	// ── Public routes ────────────────────────────
	r.POST("/api/v1/auth/send-otp", proxy(authURL+"/auth/send-otp"))
	r.POST("/api/v1/auth/verify-otp", proxy(authURL+"/auth/verify-otp"))
	r.GET("/api/v1/tents", proxy(tentURL+"/tents"))
	r.GET("/api/v1/tents/:id", func(c *gin.Context) {
		proxy(tentURL + "/tents/" + c.Param("id"))(c)
	})
	r.GET("/api/v1/tents/:id/reviews", func(c *gin.Context) {
		proxy(tentURL + "/tents/" + c.Param("id") + "/reviews")(c)
	})
	r.GET("/api/v1/coupons", proxy(bookingURL+"/coupons"))

	r.POST("/api/v1/auth/kyc", proxy(authURL+"/auth/kyc"))
    r.POST("/api/v1/auth/admin/login", proxy(authURL+"/auth/admin/login"))
    r.POST("/api/v1/auth/admin/change-password", proxy(authURL+"/auth/admin/change-password"))
	r.POST("/api/v1/auth/admin/change-username", proxy(authURL+"/auth/admin/change-username"))
	r.GET("/api/v1/admin/bookings", proxy(bookingURL+"/admin/bookings"))
    r.PUT("/api/v1/admin/bookings/:ref/status", func(c *gin.Context) { proxy(bookingURL+"/admin/bookings/"+c.Param("ref")+"/status")(c) })
    r.GET("/api/v1/admin/stats", proxy(bookingURL+"/admin/stats"))
    r.GET("/api/v1/admin/revenue/weekly", proxy(bookingURL+"/admin/revenue/weekly"))
    r.GET("/api/v1/admin/users", proxy(authURL+"/admin/users"))
    
	r.PUT("/api/v1/admin/users/:phone/block", func(c *gin.Context) { proxy(authURL+"/admin/users/"+c.Param("phone")+"/block")(c) })
	r.GET("/api/v1/admin/tents", proxy(tentURL+"/admin/tents"))
    r.POST("/api/v1/admin/tents", proxy(tentURL+"/admin/tents"))
    r.PUT("/api/v1/admin/tents/:id", func(c *gin.Context) { proxy(tentURL+"/admin/tents/"+c.Param("id"))(c) })
    r.DELETE("/api/v1/admin/tents/:id", func(c *gin.Context) { proxy(tentURL+"/admin/tents/"+c.Param("id"))(c) })
    r.GET("/api/v1/admin/coupons", proxy(bookingURL+"/admin/coupons"))
    r.POST("/api/v1/admin/coupons", proxy(bookingURL+"/admin/coupons"))
    r.PUT("/api/v1/admin/coupons/:id/toggle", func(c *gin.Context) { proxy(bookingURL+"/admin/coupons/"+c.Param("id")+"/toggle")(c) })
    r.DELETE("/api/v1/admin/coupons/:id", func(c *gin.Context) { proxy(bookingURL+"/admin/coupons/"+c.Param("id"))(c) })
	r.POST("/api/v1/admin/notifications/send", proxy(bookingURL+"/admin/notifications/send"))
	r.GET("/api/v1/admin/kyc", proxy(authURL+"/admin/kyc"))
    r.PUT("/api/v1/admin/kyc/:phone/verify", func(c *gin.Context) { proxy(authURL+"/admin/kyc/"+c.Param("phone")+"/verify")(c) })
	r.DELETE("/api/v1/admin/bookings/cancelled", proxy(bookingURL+"/admin/bookings/cancelled"))
	r.DELETE("/api/v1/admin/bookings/cancelled/all", proxy(bookingURL+"/admin/bookings/cancelled/all"))
	// ── Protected routes (JWT required) ──────────
	protected := r.Group("/api/v1")
	protected.Use(jwtMiddleware())
	{
		protected.POST("/bookings", proxy(bookingURL+"/bookings"))
		protected.GET("/bookings", proxy(bookingURL+"/bookings"))
		protected.PUT("/bookings/:ref/cancel", func(c *gin.Context) {
			proxy(bookingURL + "/bookings/" + c.Param("ref") + "/cancel")(c)
		})
		// ✅ DELETE booking (only cancelled bookings)
		protected.DELETE("/bookings/:ref", func(c *gin.Context) {
			proxy(bookingURL + "/bookings/" + c.Param("ref"))(c)
		})
		protected.POST("/coupons/validate", proxy(bookingURL+"/coupons/validate"))
		protected.POST("/orders/create", proxy(paymentURL+"/orders/create"))
		protected.POST("/payments/verify", proxy(paymentURL+"/payments/verify"))
		protected.GET("/profile", proxy(authURL+"/auth/profile"))
		protected.PUT("/profile", proxy(authURL+"/auth/profile"))
		protected.POST("/fcm-token", proxy(authURL+"/auth/fcm-token"))
		protected.POST("/tents/:id/reviews", func(c *gin.Context) {
			proxy(tentURL + "/tents/" + c.Param("id") + "/reviews")(c)
		})
	}

	port := os.Getenv("API_GATEWAY_PORT")
	if port == "" {
		port = "8080"
	}
	fmt.Printf("🚀 API Gateway running on :%s\n", port)
	r.Run(":" + port)
}

func proxy(target string) gin.HandlerFunc {
	client := &http.Client{Timeout: 30 * time.Second}
	return func(c *gin.Context) {
		body, _ := io.ReadAll(c.Request.Body)
		targetURL := target
		if c.Request.URL.RawQuery != "" {
			targetURL = target + "?" + c.Request.URL.RawQuery
		}
		req, err := http.NewRequest(c.Request.Method, targetURL, strings.NewReader(string(body)))
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "proxy error"})
			return
		}
		req.Header.Set("Content-Type", "application/json")
		if auth := c.GetHeader("Authorization"); auth != "" {
			req.Header.Set("Authorization", auth)
		}
		if phone, exists := c.Get("phone"); exists {
			req.Header.Set("X-User-Phone", fmt.Sprintf("%v", phone))
		}
		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "service unavailable"})
			return
		}
		defer resp.Body.Close()
		respBody, _ := io.ReadAll(resp.Body)
		c.Data(resp.StatusCode, "application/json", respBody)
	}
}

func jwtMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenStr := c.GetHeader("Authorization")
		if tokenStr == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "no token"})
			c.Abort()
			return
		}
		if len(tokenStr) > 7 && tokenStr[:7] == "Bearer " {
			tokenStr = tokenStr[7:]
		}
		secret := os.Getenv("JWT_SECRET")
		if secret == "" {
			secret = "kumbh2027secret"
		}
		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method")
			}
			return []byte(secret), nil
		})
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			c.Abort()
			return
		}
		claims := token.Claims.(jwt.MapClaims)
		c.Set("phone", claims["phone"])
		c.Next()
	}
}

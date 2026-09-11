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
	requireEnv("JWT_SECRET")

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

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	r.Use(corsMiddleware())
	// BUG-14: every /api/v1/admin/* (and /api/v1/auth/admin/* except
	// login) now requires a valid admin-role JWT at the gateway.
	r.Use(adminGuard())

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
	// Availability lives in booking-service (it needs the bookings
	// table), not tent-service, even though the URL reads like a
	// tent sub-resource.
	r.GET("/api/v1/tents/:id/availability", func(c *gin.Context) {
		proxy(bookingURL + "/tents/" + c.Param("id") + "/availability")(c)
	})
	r.GET("/api/v1/coupons", proxy(bookingURL+"/coupons"))

	r.POST("/api/v1/auth/kyc", proxy(authURL+"/auth/kyc"))
	r.POST("/api/v1/auth/admin/login", proxy(authURL+"/auth/admin/login"))
	r.POST("/api/v1/auth/admin/change-password", proxy(authURL+"/auth/admin/change-password"))
	r.POST("/api/v1/auth/admin/change-username", proxy(authURL+"/auth/admin/change-username"))
	r.GET("/api/v1/auth/admin/list", proxy(authURL+"/auth/admin/list"))
	r.POST("/api/v1/auth/admin/create", proxy(authURL+"/auth/admin/create"))
	// ── Push notifications / favourites / snan calendar ──
	r.GET("/api/v1/notifications/preferences", proxy(bookingURL+"/notifications/preferences"))
	r.PUT("/api/v1/notifications/preferences", proxy(bookingURL+"/notifications/preferences"))
	r.GET("/api/v1/notifications/history", proxy(bookingURL+"/notifications/history"))
	r.GET("/api/v1/favourites", proxy(bookingURL+"/favourites"))
	r.POST("/api/v1/favourites", proxy(bookingURL+"/favourites"))
	r.DELETE("/api/v1/favourites/:tentId", func(c *gin.Context) {
		proxy(bookingURL + "/favourites/" + c.Param("tentId"))(c)
	})
	r.GET("/api/v1/snan-events", proxy(bookingURL+"/snan-events"))
	r.POST("/api/v1/snan-reminders", proxy(bookingURL+"/snan-reminders"))
	r.DELETE("/api/v1/snan-reminders/:date", func(c *gin.Context) {
		proxy(bookingURL + "/snan-reminders/" + c.Param("date"))(c)
	})

	r.GET("/api/v1/admin/bookings", proxy(bookingURL+"/admin/bookings"))
	r.PUT("/api/v1/admin/bookings/:ref/status", func(c *gin.Context) { proxy(bookingURL + "/admin/bookings/" + c.Param("ref") + "/status")(c) })
	r.GET("/api/v1/admin/stats", proxy(bookingURL+"/admin/stats"))
	r.GET("/api/v1/admin/revenue/weekly", proxy(bookingURL+"/admin/revenue/weekly"))
	r.GET("/api/v1/admin/finance/dashboard", proxy(bookingURL+"/admin/finance/dashboard"))
	r.GET("/api/v1/admin/finance/bookings/:ref/accounting", func(c *gin.Context) {
		proxy(bookingURL + "/admin/finance/bookings/" + c.Param("ref") + "/accounting")(c)
	})
	r.GET("/api/v1/admin/finance/bookings/:ref/audit-log", func(c *gin.Context) {
		proxy(bookingURL + "/admin/finance/bookings/" + c.Param("ref") + "/audit-log")(c)
	})
	r.GET("/api/v1/admin/payments", proxy(bookingURL+"/admin/payments"))
	r.POST("/api/v1/admin/bookings/:ref/payments", func(c *gin.Context) {
		proxy(bookingURL + "/admin/bookings/" + c.Param("ref") + "/payments")(c)
	})
	r.GET("/api/v1/admin/revenue/summary", proxy(bookingURL+"/admin/revenue/summary"))
	r.GET("/api/v1/admin/customer-receivables", proxy(bookingURL+"/admin/customer-receivables"))

	// ── Finance & Accounting (Phase 3) ────────────────
	r.POST("/api/v1/admin/expenses", proxy(bookingURL+"/admin/expenses"))
	r.GET("/api/v1/admin/expenses", proxy(bookingURL+"/admin/expenses"))
	r.POST("/api/v1/admin/expenses/:id/reverse", func(c *gin.Context) {
		proxy(bookingURL + "/admin/expenses/" + c.Param("id") + "/reverse")(c)
	})
	r.GET("/api/v1/admin/vendor-payables", proxy(bookingURL+"/admin/vendor-payables"))
	r.POST("/api/v1/admin/expenses/:id/mark-paid", func(c *gin.Context) {
		proxy(bookingURL + "/admin/expenses/" + c.Param("id") + "/mark-paid")(c)
	})
	r.GET("/api/v1/admin/exchange-rates", proxy(bookingURL+"/admin/exchange-rates"))
	r.PUT("/api/v1/admin/exchange-rates/:currency", func(c *gin.Context) {
		proxy(bookingURL + "/admin/exchange-rates/" + c.Param("currency"))(c)
	})
	r.GET("/api/v1/admin/finance/fx-report", proxy(bookingURL+"/admin/finance/fx-report"))

	// ── Finance & Accounting (Phase 4) ────────────────
	r.GET("/api/v1/admin/gateway-summary", proxy(bookingURL+"/admin/gateway-summary"))
	r.GET("/api/v1/admin/reconciliation", proxy(bookingURL+"/admin/reconciliation"))
	r.GET("/api/v1/admin/reconciliation/exceptions", proxy(bookingURL+"/admin/reconciliation/exceptions"))
	r.POST("/api/v1/admin/bookings/:ref/bank-settlement", func(c *gin.Context) {
		proxy(bookingURL + "/admin/bookings/" + c.Param("ref") + "/bank-settlement")(c)
	})
	r.GET("/api/v1/admin/gateway-settings", proxy(bookingURL+"/admin/gateway-settings"))
	r.PUT("/api/v1/admin/gateway-settings/:gateway", func(c *gin.Context) {
		proxy(bookingURL + "/admin/gateway-settings/" + c.Param("gateway"))(c)
	})

	// ── Finance & Accounting (Phase 5) ────────────────
	r.GET("/api/v1/admin/finance/pnl", proxy(bookingURL+"/admin/finance/pnl"))
	r.GET("/api/v1/admin/finance/gst-report", proxy(bookingURL+"/admin/finance/gst-report"))
	r.GET("/api/v1/admin/invoices", proxy(bookingURL+"/admin/invoices"))
	r.GET("/api/v1/admin/invoices/:id", func(c *gin.Context) {
		proxy(bookingURL + "/admin/invoices/" + c.Param("id"))(c)
	})
	r.GET("/api/v1/admin/invoices/:id/pdf", func(c *gin.Context) {
		proxy(bookingURL + "/admin/invoices/" + c.Param("id") + "/pdf")(c)
	})
	r.POST("/api/v1/admin/invoices/:id/email", func(c *gin.Context) {
		proxy(bookingURL + "/admin/invoices/" + c.Param("id") + "/email")(c)
	})
	r.POST("/api/v1/admin/invoices/:id/credit-note", func(c *gin.Context) {
		proxy(bookingURL + "/admin/invoices/" + c.Param("id") + "/credit-note")(c)
	})
	r.POST("/api/v1/admin/invoices/:id/debit-note", func(c *gin.Context) {
		proxy(bookingURL + "/admin/invoices/" + c.Param("id") + "/debit-note")(c)
	})

	// ── Finance & Accounting (Phase 6) ────────────────
	r.GET("/api/v1/admin/ledger", proxy(bookingURL+"/admin/ledger"))
	r.GET("/api/v1/admin/bank-accounts", proxy(bookingURL+"/admin/bank-accounts"))
	r.GET("/api/v1/admin/audit-log", proxy(bookingURL+"/admin/audit-log"))
	r.GET("/api/v1/admin/reports/:type", func(c *gin.Context) {
		proxy(bookingURL + "/admin/reports/" + c.Param("type"))(c)
	})
	r.GET("/api/v1/admin/users", proxy(authURL+"/admin/users"))

	r.PUT("/api/v1/admin/users/:phone/block", func(c *gin.Context) { proxy(authURL + "/admin/users/" + c.Param("phone") + "/block")(c) })
	r.GET("/api/v1/admin/tents", proxy(tentURL+"/admin/tents"))
	r.POST("/api/v1/admin/tents", proxy(tentURL+"/admin/tents"))
	r.PUT("/api/v1/admin/tents/:id", func(c *gin.Context) { proxy(tentURL + "/admin/tents/" + c.Param("id"))(c) })
	r.DELETE("/api/v1/admin/tents/:id", func(c *gin.Context) { proxy(tentURL + "/admin/tents/" + c.Param("id"))(c) })
	r.GET("/api/v1/admin/coupons", proxy(bookingURL+"/admin/coupons"))
	r.POST("/api/v1/admin/coupons", proxy(bookingURL+"/admin/coupons"))
	r.PUT("/api/v1/admin/coupons/:id/toggle", func(c *gin.Context) { proxy(bookingURL + "/admin/coupons/" + c.Param("id") + "/toggle")(c) })
	r.DELETE("/api/v1/admin/coupons/:id", func(c *gin.Context) { proxy(bookingURL + "/admin/coupons/" + c.Param("id"))(c) })
	r.POST("/api/v1/admin/notifications/send", proxy(bookingURL+"/admin/notifications/send"))
	r.GET("/api/v1/admin/kyc", proxy(authURL+"/admin/kyc"))
	r.PUT("/api/v1/admin/kyc/:phone/verify", func(c *gin.Context) { proxy(authURL + "/admin/kyc/" + c.Param("phone") + "/verify")(c) })
	r.DELETE("/api/v1/admin/bookings/cancelled", proxy(bookingURL+"/admin/bookings/cancelled"))
	r.DELETE("/api/v1/admin/bookings/cancelled/all", proxy(bookingURL+"/admin/bookings/cancelled/all"))

	// ── Admin refunds ────────────────────────────
	r.GET("/api/v1/admin/refunds", proxy(bookingURL+"/admin/refunds"))
	r.POST("/api/v1/admin/refunds/:ref/approve", func(c *gin.Context) {
		proxy(bookingURL + "/admin/refunds/" + c.Param("ref") + "/approve")(c)
	})
	r.POST("/api/v1/admin/refunds/:ref/reject", func(c *gin.Context) {
		proxy(bookingURL + "/admin/refunds/" + c.Param("ref") + "/reject")(c)
	})
	r.POST("/api/v1/admin/refunds/:ref/retry", func(c *gin.Context) {
		proxy(bookingURL + "/admin/refunds/" + c.Param("ref") + "/retry")(c)
	})
	r.POST("/api/v1/admin/refunds/:ref/settle", func(c *gin.Context) {
		proxy(bookingURL + "/admin/refunds/" + c.Param("ref") + "/settle")(c)
	})
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
		// Refund state for one of the caller's own bookings.
		protected.GET("/bookings/:ref/refund", func(c *gin.Context) {
			proxy(bookingURL + "/bookings/" + c.Param("ref") + "/refund")(c)
		})
		// Preview the refund before confirming a cancellation.
		protected.GET("/bookings/:ref/refund-quote", func(c *gin.Context) {
			proxy(bookingURL + "/bookings/" + c.Param("ref") + "/refund-quote")(c)
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
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	runGracefully(srv, "API Gateway")
}

// Shared transport across all proxy() clients: the default http.Transport
// caps MaxIdleConnsPerHost at 2, which serialized every burst of concurrent
// requests to the same backend service behind repeated TCP handshakes and
// collapsed throughput under load testing.
var proxyTransport = &http.Transport{
	MaxIdleConns:        500,
	MaxIdleConnsPerHost: 200,
	IdleConnTimeout:     90 * time.Second,
}

func proxy(target string) gin.HandlerFunc {
	client := &http.Client{Timeout: 30 * time.Second, Transport: proxyTransport}
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
		// BUG (gateway Content-Type): this used to hardcode
		// "application/json" on every proxied request regardless of
		// what the client actually sent, silently relabeling any
		// multipart/form-data upload, an octet-stream body, or a
		// client that already set its own charset/boundary. Forward
		// the client's real Content-Type and only default to JSON
		// when the client didn't send one at all (e.g. a bodyless
		// GET/DELETE) — everything downstream already assumes JSON
		// in that case.
		if ct := c.GetHeader("Content-Type"); ct != "" {
			req.Header.Set("Content-Type", ct)
		} else {
			req.Header.Set("Content-Type", "application/json")
		}
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

		// Pass through the backend's real Content-Type (e.g.
		// application/pdf for invoice downloads) instead of
		// assuming every response is JSON, and forward
		// Content-Disposition so the browser keeps the filename.
		contentType := resp.Header.Get("Content-Type")
		if contentType == "" {
			contentType = "application/json"
		}
		if disposition := resp.Header.Get("Content-Disposition"); disposition != "" {
			c.Header("Content-Disposition", disposition)
		}
		c.Data(resp.StatusCode, contentType, respBody)
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
		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method")
			}
			return jwtSecret(), nil
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

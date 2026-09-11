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
	fmt.Println("✅ Booking Service — DB connected!")

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetConnMaxIdleTime(2 * time.Minute)

	// ── Refund policy ─────────────────────────────────────
	refundPolicy = loadRefundPolicy()
	fmt.Printf("💸 Refund policy: %s\n", refundPolicy.Describe())

	// ── Start daily reminder scheduler ────────────────────
	go startReminderScheduler()

	// ── Retry refunds the gateway rejected ────────────────
	go startRefundRetryWorker()

	// ── Auto-mark no-shows past their tent's cutoff ───────
	go startNoShowSweeper()

	// ── Hourly Kumbh news poll → push on new articles ─────
	startNewsPoller()

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	r.Use(corsMiddleware())

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "booking-service"})
	})
	r.HEAD("/health", func(c *gin.Context) {
		c.Status(200)
	})

	r.POST("/bookings", createBooking)
	r.GET("/tents/:id/availability", getTentAvailability)

	// ── Push notifications, favourites, snan calendar ──
	r.GET("/notifications/preferences", getNotificationPrefs)
	r.PUT("/notifications/preferences", setNotificationPref)
	r.GET("/notifications/history", getNotificationHistory)
	r.GET("/favourites", listFavourites)
	r.POST("/favourites", addFavourite)
	r.DELETE("/favourites/:tentId", removeFavourite)
	r.GET("/snan-events", listSnanEvents)
	r.POST("/snan-reminders", addSnanReminder)
	r.DELETE("/snan-reminders/:date", removeSnanReminder)
	r.GET("/bookings", myBookings)
	r.PUT("/bookings/:ref/cancel", cancelBooking)
	r.DELETE("/bookings/:ref", deleteBooking)

	// ── Refunds ───────────────────────────────────────────
	r.GET("/bookings/:ref/refund", getBookingRefund)
	r.GET("/bookings/:ref/refund-quote", getRefundQuote)
	r.POST("/coupons/validate", validateCoupon)
	r.GET("/coupons", listCoupons)

	// BUG-15: every /admin/* route now requires its own valid admin
	// JWT (requireAdmin, rbac.go), not just api-gateway's adminGuard.
	// requireSuperAdmin() still layers a stricter role check on top
	// for the four money-moving actions it already gated.
	admin := r.Group("/admin")
	admin.Use(requireAdmin())

	admin.GET("/bookings", adminGetBookings)
	admin.PUT("/bookings/:ref/status", adminUpdateBookingStatus)
	admin.PUT("/bookings/:ref/check-in", adminCheckInBooking)
	admin.GET("/stats", adminGetStats)
	admin.GET("/revenue/weekly", adminWeeklyRevenue)

	// ── Finance & Accounting (Phase 1) ────────────────
	admin.GET("/finance/dashboard", adminFinanceDashboard)
	admin.GET("/finance/bookings/:ref/accounting", adminBookingAccounting)
	admin.GET("/finance/bookings/:ref/audit-log", adminBookingAuditLog)

	// ── Finance & Accounting (Phase 2) ────────────────
	admin.GET("/payments", adminPaymentTracking)
	admin.POST("/bookings/:ref/payments", adminRecordPayment)
	admin.GET("/revenue/summary", adminRevenueSummary)
	admin.GET("/customer-receivables", adminCustomerReceivables)

	// ── Finance & Accounting (Phase 3) ────────────────
	admin.POST("/expenses", adminCreateExpense)
	admin.GET("/expenses", adminListExpenses)
	admin.POST("/expenses/:id/reverse", requireSuperAdmin(), adminReverseExpense)
	admin.GET("/vendor-payables", adminVendorPayables)
	admin.POST("/expenses/:id/mark-paid", adminMarkExpensePaid)
	admin.GET("/exchange-rates", adminGetExchangeRates)
	admin.PUT("/exchange-rates/:currency", adminSetExchangeRate)
	admin.GET("/finance/fx-report", adminFXReport)

	// ── Finance & Accounting (Phase 4) ────────────────
	admin.GET("/gateway-summary", adminGatewaySummary)
	admin.GET("/reconciliation", adminReconciliation)
	admin.GET("/reconciliation/exceptions", adminReconciliationExceptions)
	admin.POST("/bookings/:ref/bank-settlement", adminRecordBankSettlement)
	admin.GET("/gateway-settings", adminGetGatewaySettings)
	admin.PUT("/gateway-settings/:gateway", adminSetGatewaySettings)

	// ── Finance & Accounting (Phase 5) ────────────────
	admin.GET("/finance/pnl", adminPnL)
	admin.GET("/finance/gst-report", adminGSTReport)
	admin.GET("/invoices", adminListInvoices)
	admin.GET("/invoices/:id", adminGetInvoice)
	admin.GET("/invoices/:id/pdf", adminInvoicePDF)
	admin.POST("/invoices/:id/email", adminEmailInvoice)
	admin.POST("/invoices/:id/credit-note", requireSuperAdmin(), adminIssueCreditNote)
	admin.POST("/invoices/:id/debit-note", requireSuperAdmin(), adminIssueDebitNote)

	// ── Finance & Accounting (Phase 6) ────────────────
	admin.GET("/ledger", adminGetLedger)
	admin.GET("/bank-accounts", adminGetBankAccounts)
	admin.GET("/reports/:type", adminReport)
	admin.GET("/audit-log", adminGetAuditLog)

	admin.GET("/coupons", adminGetCoupons)
	admin.POST("/coupons", adminCreateCoupon)
	admin.PUT("/coupons/:id/toggle", adminToggleCoupon)
	admin.DELETE("/coupons/:id", adminDeleteCoupon)
	admin.POST("/notifications/send", adminSendNotification)
	admin.DELETE("/bookings/cancelled", adminClearCancelledBookings)
	admin.DELETE("/bookings/cancelled/all", adminClearAllCancelledBookings)

	admin.GET("/refunds", adminListRefunds)
	admin.POST("/refunds/:ref/approve", requireSuperAdmin(), adminApproveRefund)
	admin.POST("/refunds/:ref/reject", requireSuperAdmin(), adminRejectRefund)
	admin.POST("/refunds/:ref/retry", adminRetryRefund)
	admin.POST("/refunds/:ref/settle", adminMarkRefundSettled)

	port := os.Getenv("BOOKING_SERVICE_PORT")
	if port == "" {
		port = "8083"
	}
	fmt.Printf("🚀 Booking Service running on :%s\n", port)
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
		runNotificationJobs()
	}
}

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
	r.GET("/admin/bookings", adminGetBookings)
	r.PUT("/admin/bookings/:ref/status", adminUpdateBookingStatus)
	r.PUT("/admin/bookings/:ref/check-in", adminCheckInBooking)
	r.GET("/admin/stats", adminGetStats)
	r.GET("/admin/revenue/weekly", adminWeeklyRevenue)

	// ── Finance & Accounting (Phase 1) ────────────────
	r.GET("/admin/finance/dashboard", adminFinanceDashboard)
	r.GET("/admin/finance/bookings/:ref/accounting", adminBookingAccounting)
	r.GET("/admin/finance/bookings/:ref/audit-log", adminBookingAuditLog)

	// ── Finance & Accounting (Phase 2) ────────────────
	r.GET("/admin/payments", adminPaymentTracking)
	r.POST("/admin/bookings/:ref/payments", adminRecordPayment)
	r.GET("/admin/revenue/summary", adminRevenueSummary)
	r.GET("/admin/customer-receivables", adminCustomerReceivables)

	// ── Finance & Accounting (Phase 3) ────────────────
	r.POST("/admin/expenses", adminCreateExpense)
	r.GET("/admin/expenses", adminListExpenses)
	r.POST("/admin/expenses/:id/reverse", requireSuperAdmin(), adminReverseExpense)
	r.GET("/admin/vendor-payables", adminVendorPayables)
	r.POST("/admin/expenses/:id/mark-paid", adminMarkExpensePaid)
	r.GET("/admin/exchange-rates", adminGetExchangeRates)
	r.PUT("/admin/exchange-rates/:currency", adminSetExchangeRate)
	r.GET("/admin/finance/fx-report", adminFXReport)

	// ── Finance & Accounting (Phase 4) ────────────────
	r.GET("/admin/gateway-summary", adminGatewaySummary)
	r.GET("/admin/reconciliation", adminReconciliation)
	r.GET("/admin/reconciliation/exceptions", adminReconciliationExceptions)
	r.POST("/admin/bookings/:ref/bank-settlement", adminRecordBankSettlement)
	r.GET("/admin/gateway-settings", adminGetGatewaySettings)
	r.PUT("/admin/gateway-settings/:gateway", adminSetGatewaySettings)

	// ── Finance & Accounting (Phase 5) ────────────────
	r.GET("/admin/finance/pnl", adminPnL)
	r.GET("/admin/finance/gst-report", adminGSTReport)
	r.GET("/admin/invoices", adminListInvoices)
	r.GET("/admin/invoices/:id", adminGetInvoice)
	r.GET("/admin/invoices/:id/pdf", adminInvoicePDF)
	r.POST("/admin/invoices/:id/email", adminEmailInvoice)
	r.POST("/admin/invoices/:id/credit-note", requireSuperAdmin(), adminIssueCreditNote)
	r.POST("/admin/invoices/:id/debit-note", requireSuperAdmin(), adminIssueDebitNote)

	// ── Finance & Accounting (Phase 6) ────────────────
	r.GET("/admin/ledger", adminGetLedger)
	r.GET("/admin/bank-accounts", adminGetBankAccounts)
	r.GET("/admin/reports/:type", adminReport)
	r.GET("/admin/audit-log", adminGetAuditLog)

	r.GET("/admin/coupons", adminGetCoupons)
	r.POST("/admin/coupons", adminCreateCoupon)
	r.PUT("/admin/coupons/:id/toggle", adminToggleCoupon)
	r.DELETE("/admin/coupons/:id", adminDeleteCoupon)
	r.POST("/admin/notifications/send", adminSendNotification)
	r.DELETE("/admin/bookings/cancelled", adminClearCancelledBookings)
	r.DELETE("/admin/bookings/cancelled/all", adminClearAllCancelledBookings)

	r.GET("/admin/refunds", adminListRefunds)
	r.POST("/admin/refunds/:ref/approve", requireSuperAdmin(), adminApproveRefund)
	r.POST("/admin/refunds/:ref/reject", requireSuperAdmin(), adminRejectRefund)
	r.POST("/admin/refunds/:ref/retry", adminRetryRefund)
	r.POST("/admin/refunds/:ref/settle", adminMarkRefundSettled)

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

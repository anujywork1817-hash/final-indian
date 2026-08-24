package main

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ── Profit & Loss + Tax/GST — Phase 5 ────────────────────
//
// Pure aggregation over bookings/refunds/expenses/payments —
// no new tables. Both endpoints are read-only reports; nothing
// here writes anything.

func periodGroupExpr(period string) (string, string) {
	switch period {
	case "daily":
		return "TO_CHAR(%s, 'YYYY-MM-DD')", "daily"
	case "weekly":
		return "TO_CHAR(%s, 'IYYY-\"W\"IW')", "weekly"
	case "yearly":
		return "TO_CHAR(%s, 'YYYY')", "yearly"
	default:
		return "TO_CHAR(%s, 'YYYY-MM')", "monthly"
	}
}

// GET /admin/finance/pnl?period=daily|weekly|monthly|yearly
//
// Revenue: Gross Booking Value − Refunds = Net Revenue.
// Expenses: Operating Expenses + Gateway Charges = Total Expenses.
// Net Operating Profit = Net Revenue − Total Expenses.
//
// Deliberately NOT "the" profit — see the "note" field in the
// response. Other Income, Depreciation, income tax, insurance,
// rent (if not already itemized as an Operating Expense), and FX
// gain/loss (Phase 3's own report) all sit outside this number.
func adminPnL(c *gin.Context) {
	periodExprTmpl, periodLabel := periodGroupExpr(c.DefaultQuery("period", "monthly"))
	bookingGroupExpr := fmt.Sprintf(periodExprTmpl, "b.created_at")
	expenseGroupExpr := fmt.Sprintf(periodExprTmpl, "e.expense_date")
	paymentGroupExpr := fmt.Sprintf(periodExprTmpl, "p.created_at")
	refundGroupExpr := fmt.Sprintf(periodExprTmpl, "r.created_at")

	type row struct {
		Period             string  `json:"period"`
		GrossBookingValue  float64 `json:"gross_booking_value"`
		Refunds            float64 `json:"refunds"`
		NetRevenue         float64 `json:"net_revenue"`
		OperatingExpenses  float64 `json:"operating_expenses"`
		GatewayCharges     float64 `json:"gateway_charges"`
		TotalExpenses      float64 `json:"total_expenses"`
		NetOperatingProfit float64 `json:"net_operating_profit"`
	}
	byPeriod := map[string]*row{}
	order := []string{}
	get := func(key string) *row {
		if r, ok := byPeriod[key]; ok {
			return r
		}
		r := &row{Period: key}
		byPeriod[key] = r
		order = append(order, key)
		return r
	}

	// Gross booking value per period.
	rows, _ := db.Query(`
		SELECT ` + bookingGroupExpr + `, COALESCE(SUM(b.total_amount), 0)
		FROM bookings b WHERE b.status != 'cancelled' AND b.status != 'pending'
		GROUP BY 1
	`)
	if rows != nil {
		for rows.Next() {
			var key string
			var amount float64
			if rows.Scan(&key, &amount) == nil {
				get(key).GrossBookingValue = amount
			}
		}
		rows.Close()
	}

	// Refunds (settled only) per period.
	rows, _ = db.Query(`
		SELECT ` + refundGroupExpr + `, COALESCE(SUM(r.refund_amount_paise), 0) / 100.0
		FROM refunds r WHERE r.status = 'succeeded'
		GROUP BY 1
	`)
	if rows != nil {
		for rows.Next() {
			var key string
			var amount float64
			if rows.Scan(&key, &amount) == nil {
				get(key).Refunds = amount
			}
		}
		rows.Close()
	}

	// Operating expenses (net of reversals — a reversal is already
	// a negative row, so a plain SUM nets it out) per period.
	rows, _ = db.Query(`
		SELECT ` + expenseGroupExpr + `, COALESCE(SUM(e.amount + e.tax), 0)
		FROM expenses e
		GROUP BY 1
	`)
	if rows != nil {
		for rows.Next() {
			var key string
			var amount float64
			if rows.Scan(&key, &amount) == nil {
				get(key).OperatingExpenses = amount
			}
		}
		rows.Close()
	}

	// Gateway charges (Razorpay fee + tax on fee) per period.
	rows, _ = db.Query(`
		SELECT ` + paymentGroupExpr + `, p.payment_mode, COALESCE(SUM(p.amount), 0)
		FROM payments p WHERE p.status = 'success'
		GROUP BY 1, 2
	`)
	if rows != nil {
		for rows.Next() {
			var key, gateway string
			var gross float64
			if rows.Scan(&key, &gateway, &gross) == nil {
				feePaise := gatewayFeePaiseFor(gateway, int64(gross*100+0.5))
				get(key).GatewayCharges += float64(feePaise) / 100.0
			}
		}
		rows.Close()
	}

	result := make([]row, 0, len(order))
	for _, key := range order {
		r := byPeriod[key]
		r.NetRevenue = r.GrossBookingValue - r.Refunds
		r.TotalExpenses = r.OperatingExpenses + r.GatewayCharges
		r.NetOperatingProfit = r.NetRevenue - r.TotalExpenses
		result = append(result, *r)
	}

	c.JSON(http.StatusOK, gin.H{
		"period_type": periodLabel,
		"rows":        result,
		"note": "Net Operating Profit only — excludes Other Income, Depreciation, " +
			"income tax, insurance/rent not itemized as an Operating Expense, and " +
			"FX gain/loss (see GET /admin/finance/fx-report separately).",
	})
}

// GET /admin/finance/gst-report?period=daily|weekly|monthly|yearly
//
// GST Collected (output tax on bookings) vs Input Tax Credit
// (GST paid on operating expenses). CGST/SGST are split evenly
// from the total — this app has always charged intra-state GST
// (see booking creation's 6%+6% / 9%+9% split) and never
// collects a customer's billing state, so IGST is always 0 here.
// A foreign-currency booking is flagged as a POSSIBLE export of
// service, never auto zero-rated — that determination needs an
// actual CA/accountant to confirm the legal conditions (payment
// in convertible foreign exchange, LUT/bond on file, etc.).
func adminGSTReport(c *gin.Context) {
	periodExprTmpl, periodLabel := periodGroupExpr(c.DefaultQuery("period", "monthly"))
	bookingGroupExpr := fmt.Sprintf(periodExprTmpl, "b.created_at")
	expenseGroupExpr := fmt.Sprintf(periodExprTmpl, "e.expense_date")

	type row struct {
		Period              string  `json:"period"`
		TaxableValue        float64 `json:"taxable_value"`
		GSTCollected        float64 `json:"gst_collected"`
		CGST                float64 `json:"cgst"`
		SGST                float64 `json:"sgst"`
		IGST                float64 `json:"igst"`
		InputTaxCredit      float64 `json:"input_tax_credit"`
		NetGSTPayable       float64 `json:"net_gst_payable"`
		ForeignBookingCount int     `json:"foreign_booking_count"`
	}
	byPeriod := map[string]*row{}
	order := []string{}
	get := func(key string) *row {
		if r, ok := byPeriod[key]; ok {
			return r
		}
		r := &row{Period: key}
		byPeriod[key] = r
		order = append(order, key)
		return r
	}

	rows, _ := db.Query(`
		SELECT ` + bookingGroupExpr + `,
		       COALESCE(SUM(b.base_amount - b.discount), 0),
		       COALESCE(SUM(b.tax), 0),
		       COUNT(*) FILTER (WHERE b.currency != 'INR')
		FROM bookings b WHERE b.status != 'cancelled' AND b.status != 'pending'
		GROUP BY 1
	`)
	if rows != nil {
		for rows.Next() {
			var key string
			var taxable, gst float64
			var foreignCount int
			if rows.Scan(&key, &taxable, &gst, &foreignCount) == nil {
				r := get(key)
				r.TaxableValue = taxable
				r.GSTCollected = gst
				r.CGST = gst / 2
				r.SGST = gst / 2
				r.ForeignBookingCount = foreignCount
			}
		}
		rows.Close()
	}

	rows, _ = db.Query(`
		SELECT ` + expenseGroupExpr + `, COALESCE(SUM(e.tax), 0)
		FROM expenses e
		GROUP BY 1
	`)
	if rows != nil {
		for rows.Next() {
			var key string
			var itc float64
			if rows.Scan(&key, &itc) == nil {
				get(key).InputTaxCredit = itc
			}
		}
		rows.Close()
	}

	result := make([]row, 0, len(order))
	for _, key := range order {
		r := byPeriod[key]
		r.NetGSTPayable = r.GSTCollected - r.InputTaxCredit
		result = append(result, *r)
	}

	c.JSON(http.StatusOK, gin.H{
		"period_type": periodLabel,
		"rows":        result,
		"note": "CGST/SGST split assumes intra-state supply (this app never collects a " +
			"customer's billing state); IGST is always 0. foreign_booking_count flags " +
			"bookings that MAY qualify as export of service — verify the legal conditions " +
			"with a CA before treating them as zero-rated.",
	})
}

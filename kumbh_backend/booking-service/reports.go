package main

import (
	"bytes"
	"database/sql"
	"encoding/csv"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jung-kurt/gofpdf"
)

// ── Reports — Phase 6 ─────────────────────────────────────
//
// Six report types, each exportable as CSV (which Excel opens
// natively — no separate .xlsx library) and as PDF. All six are
// read-only views over data that already exists from earlier
// phases; nothing here computes anything new.

type reportTable struct {
	Title   string
	Columns []string
	Rows    [][]string
}

var reportTitles = map[string]string{
	"sales":               "Sales, Booking & Payment Report",
	"outstanding-refund":  "Outstanding & Refund Report",
	"expense-gst":         "Expense Report (with GST)",
	"invoice-settlement":  "Invoice & Settlement Report",
	"bank-reconciliation": "Bank Reconciliation Report",
	"currency-tax":        "Currency & Tax Report",
}

// GET /admin/reports/:type?format=csv|pdf
func adminReport(c *gin.Context) {
	reportType := c.Param("type")
	format := c.DefaultQuery("format", "csv")

	table, err := buildReportTable(reportType)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	switch format {
	case "pdf":
		pdfBytes, err := renderReportPDF(table)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate PDF"})
			return
		}
		c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s.pdf"`, reportType))
		c.Data(http.StatusOK, "application/pdf", pdfBytes)
	default:
		csvBytes := renderReportCSV(table)
		c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s.csv"`, reportType))
		c.Data(http.StatusOK, "text/csv", csvBytes)
	}
}

func buildReportTable(reportType string) (*reportTable, error) {
	title, ok := reportTitles[reportType]
	if !ok {
		return nil, fmt.Errorf("unknown report type %q", reportType)
	}
	table := &reportTable{Title: title}

	switch reportType {
	case "sales":
		table.Columns = []string{"Booking Ref", "Customer", "Tent", "Check-in", "Check-out", "Booking Value", "Received", "Status", "Payment Status"}
		rows, err := db.Query(`
			SELECT b.booking_ref, COALESCE(b.guest_name, b.phone), b.tent_name,
			       b.check_in::text, b.check_out::text, b.total_amount, b.status, b.payment_id
			FROM bookings b ORDER BY b.created_at DESC
		`)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var ref, customer, tent, checkIn, checkOut, status string
			var total float64
			var paymentID sql.NullString
			if rows.Scan(&ref, &customer, &tent, &checkIn, &checkOut, &total, &status, &paymentID) != nil {
				continue
			}
			paidPaise := paidAmountPaise(ref, status, total, paymentID)
			table.Rows = append(table.Rows, []string{
				ref, customer, tent, checkIn, checkOut,
				money(total), money(float64(paidPaise) / 100.0), status,
				paymentStatusFor(status, int64(total*100+0.5), paidPaise, 0),
			})
		}

	case "outstanding-refund":
		table.Columns = []string{"Booking Ref", "Customer", "Total Value", "Outstanding", "Refund Amount", "Refund Status", "Refund Reason", "Reviewed By", "Payment Status"}
		rows, err := db.Query(`
			SELECT b.booking_ref, COALESCE(b.guest_name, b.phone), b.total_amount, b.status, b.payment_id
			FROM bookings b ORDER BY b.created_at DESC
		`)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var ref, customer, status string
			var total float64
			var paymentID sql.NullString
			if rows.Scan(&ref, &customer, &total, &status, &paymentID) != nil {
				continue
			}
			paidPaise := paidAmountPaise(ref, status, total, paymentID)
			totalPaise := int64(total*100 + 0.5)
			outstandingPaise := totalPaise - paidPaise
			if outstandingPaise < 0 || status == "cancelled" || status == "no_show" {
				outstandingPaise = 0
			}
			var refundAmount float64
			var refundStatus string
			var approvalReason, rejectionReason, reviewedBy sql.NullString
			db.QueryRow(`
				SELECT refund_amount_paise/100.0, status, approval_reason, rejection_reason, reviewed_by
				FROM refunds WHERE booking_ref = $1
			`, ref).Scan(&refundAmount, &refundStatus, &approvalReason, &rejectionReason, &reviewedBy)
			// Whichever decision was actually taken is the one worth
			// printing — an approved refund has no rejection reason
			// and vice versa.
			refundReason := approvalReason.String
			if refundReason == "" {
				refundReason = rejectionReason.String
			}
			table.Rows = append(table.Rows, []string{
				ref, customer, money(total), money(float64(outstandingPaise) / 100.0),
				money(refundAmount), refundStatus, refundReason, reviewedBy.String,
				paymentStatusFor(status, totalPaise, paidPaise, int64(refundAmount*100+0.5)),
			})
		}

	case "expense-gst":
		table.Columns = []string{"Date", "Category", "Amount", "Tax (GST)", "Payment Mode", "Approved By", "Note"}
		rows, err := db.Query(`
			SELECT expense_date::text, category, amount, tax, payment_mode, approved_by, COALESCE(note,'')
			FROM expenses ORDER BY expense_date DESC, id DESC
		`)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var date, category, mode, approvedBy, note string
			var amount, tax float64
			if rows.Scan(&date, &category, &amount, &tax, &mode, &approvedBy, &note) != nil {
				continue
			}
			table.Rows = append(table.Rows, []string{date, category, money(amount), money(tax), mode, approvedBy, note})
		}

	case "invoice-settlement":
		table.Columns = []string{"Invoice No", "Booking Ref", "Customer", "Total", "Currency", "Payment Status", "Bank Settled", "Settlement Date"}
		rows, err := db.Query(`
			SELECT invoice_number, booking_ref, customer_name, total_amount, currency,
			       COALESCE(payment_status_at_issue,'')
			FROM invoices ORDER BY created_at DESC
		`)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var invNum, ref, customer, currency, paymentStatus string
			var total float64
			if rows.Scan(&invNum, &ref, &customer, &total, &currency, &paymentStatus) != nil {
				continue
			}
			var settledAmount float64
			var settlementDate string
			db.QueryRow(`SELECT amount, settlement_date::text FROM bank_settlements WHERE booking_ref = $1`, ref).Scan(&settledAmount, &settlementDate)
			settledStr := "—"
			if settledAmount > 0 {
				settledStr = money(settledAmount)
			}
			if settlementDate == "" {
				settlementDate = "—"
			}
			table.Rows = append(table.Rows, []string{invNum, ref, customer, money(total), currency, paymentStatus, settledStr, settlementDate})
		}

	case "bank-reconciliation":
		table.Columns = []string{"Booking Ref", "Gateway", "Booking Amount", "Gateway Amount", "Fee+Tax", "Expected Net", "Bank Settled", "Status"}
		recRows, err := buildReconciliationRows()
		if err != nil {
			return nil, err
		}
		for _, r := range recRows {
			settled := "—"
			if r.BankSettledAmount > 0 {
				settled = money(r.BankSettledAmount)
			}
			table.Rows = append(table.Rows, []string{
				r.BookingRef, r.Gateway, money(r.BookingAmount), money(r.GatewayAmount),
				money(r.FeeAndTax), money(r.ExpectedNet), settled, r.Status,
			})
		}

	case "currency-tax":
		table.Columns = []string{"Booking Ref", "Currency", "Foreign Amount", "Booked Rate", "Current Rate", "Taxable Value", "GST", "FX Gain/Loss"}
		rows, err := db.Query(`
			SELECT b.booking_ref, b.currency, b.foreign_amount, b.exchange_rate,
			       b.base_amount - b.discount, b.tax
			FROM bookings b
			WHERE b.currency != 'INR' AND b.foreign_amount IS NOT NULL
			ORDER BY b.created_at DESC
		`)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		currentRates := map[string]float64{}
		rateRows, _ := db.Query(`SELECT currency_code, rate_to_inr FROM exchange_rates`)
		if rateRows != nil {
			for rateRows.Next() {
				var code string
				var rate float64
				if rateRows.Scan(&code, &rate) == nil {
					currentRates[code] = rate
				}
			}
			rateRows.Close()
		}
		for rows.Next() {
			var ref, currency string
			var foreignAmount, bookedRate, taxable, gst float64
			if rows.Scan(&ref, &currency, &foreignAmount, &bookedRate, &taxable, &gst) != nil {
				continue
			}
			currentRate := currentRates[currency]
			if currentRate == 0 {
				currentRate = bookedRate
			}
			gainLoss := foreignAmount*currentRate - foreignAmount*bookedRate
			table.Rows = append(table.Rows, []string{
				ref, currency, fmt.Sprintf("%.2f", foreignAmount), fmt.Sprintf("%.4f", bookedRate),
				fmt.Sprintf("%.4f", currentRate), money(taxable), money(gst), money(gainLoss),
			})
		}
	}

	return table, nil
}

func money(v float64) string {
	return fmt.Sprintf("%.2f", v)
}

func renderReportCSV(table *reportTable) []byte {
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	w.Write(table.Columns)
	for _, row := range table.Rows {
		w.Write(row)
	}
	w.Flush()
	return buf.Bytes()
}

func renderReportPDF(table *reportTable) ([]byte, error) {
	pdf := gofpdf.New("L", "mm", "A4", "") // landscape — these tables are wide
	pdf.AddPage()
	pdf.SetFont("Arial", "B", 14)
	pdf.CellFormat(0, 10, table.Title, "", 1, "L", false, 0, "")
	pdf.Ln(2)

	colCount := len(table.Columns)
	if colCount == 0 {
		colCount = 1
	}
	pageWidth, _ := pdf.GetPageSize()
	margin, _, _, _ := pdf.GetMargins()
	usableWidth := pageWidth - 2*margin
	colWidth := usableWidth / float64(colCount)

	pdf.SetFont("Arial", "B", 8)
	pdf.SetFillColor(235, 235, 235)
	for _, col := range table.Columns {
		pdf.CellFormat(colWidth, 7, col, "1", 0, "L", true, 0, "")
	}
	pdf.Ln(-1)

	pdf.SetFont("Arial", "", 7)
	for _, row := range table.Rows {
		for _, cell := range row {
			pdf.CellFormat(colWidth, 6, truncateForPDF(cell, 40), "1", 0, "L", false, 0, "")
		}
		pdf.Ln(-1)
	}
	if len(table.Rows) == 0 {
		pdf.CellFormat(usableWidth, 8, "No data", "1", 1, "C", false, 0, "")
	}

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// truncateForPDF shortens s to at most n characters, appending an
// ellipsis if it had to cut anything.
//
// BUG: this used to count and slice by byte length (`len(s)`,
// `s[:n-1]`). Guest names and addresses in this app are routinely
// non-ASCII (Devanagari, accented Latin, emoji), where one character
// can be 2-4 bytes — a byte-index cut lands mid-rune, producing
// truncated/invalid UTF-8 that renders as mojibake or a replacement
// glyph (�) in the exported PDF report. Counting runes instead of
// bytes always cuts on a character boundary.
func truncateForPDF(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	if n <= 0 {
		return ""
	}
	return string(r[:n-1]) + "…"
}

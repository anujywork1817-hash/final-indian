package main

import (
	"bytes"
	"database/sql"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/smtp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jung-kurt/gofpdf"
)

// ── Invoice Management — Phase 5 ─────────────────────────
//
// One invoice per booking, generated automatically the moment a
// booking is CONFIRMED — the same two trigger points the
// confirmation email already uses (payment-service's
// verifyPayment for online payment, this service's
// adminUpdateBookingStatus for cash). Immutable once issued: no
// UPDATE path exists anywhere for the invoices table — a
// correction is a credit or debit note against it instead.

// generateInvoiceForBooking is idempotent (ON CONFLICT DO
// NOTHING on booking_ref) so it's safe to call even if a booking
// somehow gets confirmed twice.
func generateInvoiceForBooking(bookingRef string) {
	var phone, tentName, location, status, currency string
	var checkIn, checkOut string
	var baseAmount, discount, tax, totalAmount float64
	var guestName, paymentID sql.NullString
	err := db.QueryRow(`
		SELECT phone, tent_name, COALESCE(location,''), status,
		       check_in::text, check_out::text,
		       base_amount, discount, tax, total_amount, guest_name, currency, payment_id
		FROM bookings WHERE booking_ref = $1
	`, bookingRef).Scan(&phone, &tentName, &location, &status, &checkIn, &checkOut,
		&baseAmount, &discount, &tax, &totalAmount, &guestName, &currency, &paymentID)
	if err != nil {
		fmt.Printf("⚠️  invoice: could not load booking %s: %v\n", bookingRef, err)
		return
	}

	var country string
	db.QueryRow(`SELECT COALESCE(country,'India') FROM users WHERE phone = $1`, phone).Scan(&country)
	if country == "" {
		country = "India"
	}

	customerName := guestName.String
	if customerName == "" {
		customerName = phone
	}

	var invoiceSeq int
	if err := db.QueryRow(`SELECT nextval('invoice_number_seq')`).Scan(&invoiceSeq); err != nil {
		fmt.Printf("⚠️  invoice: could not allocate invoice number for %s: %v\n", bookingRef, err)
		return
	}
	invoiceNumber := fmt.Sprintf("INV-2027-%05d", invoiceSeq)

	paidPaise := paidAmountPaise(bookingRef, status, totalAmount, paymentID)
	var refundedPaise int64
	db.QueryRow(`SELECT refund_amount_paise FROM refunds WHERE booking_ref = $1 AND status = 'succeeded'`, bookingRef).Scan(&refundedPaise)
	totalPaise := int64(totalAmount*100 + 0.5)
	paymentStatus := paymentStatusFor(status, totalPaise, paidPaise, refundedPaise)

	_, err = db.Exec(`
		INSERT INTO invoices
			(invoice_number, booking_ref, customer_name, customer_phone, billing_country,
			 tent_name, location, check_in, check_out, base_amount, tax, total_amount,
			 currency, payment_status_at_issue)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
		ON CONFLICT (booking_ref) DO NOTHING
	`, invoiceNumber, bookingRef, customerName, phone, country,
		tentName, location, checkIn, checkOut, baseAmount-discount, tax, totalAmount,
		currency, paymentStatus,
	)
	if err != nil {
		fmt.Printf("⚠️  invoice: could not create invoice for %s: %v\n", bookingRef, err)
		return
	}
	fmt.Printf("🧾 invoice %s generated for booking %s\n", invoiceNumber, bookingRef)
}

type invoiceNote struct {
	NoteNumber string  `json:"note_number"`
	NoteType   string  `json:"note_type"`
	Amount     float64 `json:"amount"`
	Reason     string  `json:"reason"`
	IssuedBy   string  `json:"issued_by"`
	CreatedAt  string  `json:"created_at"`
}

type invoiceDetail struct {
	ID                   int           `json:"id"`
	InvoiceNumber        string        `json:"invoice_number"`
	BookingRef           string        `json:"booking_ref"`
	CustomerName         string        `json:"customer_name"`
	CustomerPhone        string        `json:"customer_phone"`
	BillingCountry       string        `json:"billing_country"`
	TentName             string        `json:"tent_name"`
	Location             string        `json:"location"`
	CheckIn              string        `json:"check_in"`
	CheckOut             string        `json:"check_out"`
	BaseAmount           float64       `json:"base_amount"`
	Tax                  float64       `json:"tax"`
	TotalAmount          float64       `json:"total_amount"`
	Currency             string        `json:"currency"`
	PaymentStatusAtIssue string        `json:"payment_status_at_issue"`
	CreatedAt            string        `json:"created_at"`
	Notes                []invoiceNote `json:"notes"`
	AdjustedTotal        float64       `json:"adjusted_total"`
}

func loadInvoiceDetail(id string) (*invoiceDetail, error) {
	var inv invoiceDetail
	var location sql.NullString
	err := db.QueryRow(`
		SELECT id, invoice_number, booking_ref, customer_name, customer_phone, billing_country,
		       tent_name, location, check_in::text, check_out::text, base_amount, tax, total_amount,
		       currency, COALESCE(payment_status_at_issue,''), created_at::text
		FROM invoices WHERE id = $1
	`, id).Scan(&inv.ID, &inv.InvoiceNumber, &inv.BookingRef, &inv.CustomerName, &inv.CustomerPhone,
		&inv.BillingCountry, &inv.TentName, &location, &inv.CheckIn, &inv.CheckOut,
		&inv.BaseAmount, &inv.Tax, &inv.TotalAmount, &inv.Currency, &inv.PaymentStatusAtIssue, &inv.CreatedAt)
	if err != nil {
		return nil, err
	}
	inv.Location = location.String

	rows, err := db.Query(`
		SELECT note_number, note_type, amount, reason, issued_by, created_at::text
		FROM credit_debit_notes WHERE invoice_id = $1 ORDER BY created_at ASC
	`, inv.ID)
	inv.Notes = []invoiceNote{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var n invoiceNote
			if rows.Scan(&n.NoteNumber, &n.NoteType, &n.Amount, &n.Reason, &n.IssuedBy, &n.CreatedAt) == nil {
				inv.Notes = append(inv.Notes, n)
			}
		}
	}

	adjusted := inv.TotalAmount
	for _, n := range inv.Notes {
		if n.NoteType == "credit" {
			adjusted -= n.Amount
		} else {
			adjusted += n.Amount
		}
	}
	inv.AdjustedTotal = adjusted

	return &inv, nil
}

// GET /admin/invoices
func adminListInvoices(c *gin.Context) {
	rows, err := db.Query(`
		SELECT id, invoice_number, booking_ref, customer_name, tent_name, total_amount,
		       currency, COALESCE(payment_status_at_issue,''), created_at::text
		FROM invoices ORDER BY created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch invoices"})
		return
	}
	defer rows.Close()

	type row struct {
		ID            int     `json:"id"`
		InvoiceNumber string  `json:"invoice_number"`
		BookingRef    string  `json:"booking_ref"`
		CustomerName  string  `json:"customer_name"`
		TentName      string  `json:"tent_name"`
		TotalAmount   float64 `json:"total_amount"`
		Currency      string  `json:"currency"`
		PaymentStatus string  `json:"payment_status_at_issue"`
		CreatedAt     string  `json:"created_at"`
	}
	out := []row{}
	for rows.Next() {
		var r row
		if rows.Scan(&r.ID, &r.InvoiceNumber, &r.BookingRef, &r.CustomerName, &r.TentName,
			&r.TotalAmount, &r.Currency, &r.PaymentStatus, &r.CreatedAt) == nil {
			out = append(out, r)
		}
	}
	c.JSON(http.StatusOK, gin.H{"invoices": out, "total": len(out)})
}

// GET /admin/invoices/:id
func adminGetInvoice(c *gin.Context) {
	inv, err := loadInvoiceDetail(c.Param("id"))
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "invoice not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch invoice"})
		return
	}
	c.JSON(http.StatusOK, inv)
}

// GET /admin/invoices/:id/pdf
func adminInvoicePDF(c *gin.Context) {
	inv, err := loadInvoiceDetail(c.Param("id"))
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "invoice not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch invoice"})
		return
	}

	pdfBytes, err := buildInvoicePDF(inv)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate PDF"})
		return
	}

	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s.pdf"`, inv.InvoiceNumber))
	c.Data(http.StatusOK, "application/pdf", pdfBytes)
}

func buildInvoicePDF(inv *invoiceDetail) ([]byte, error) {
	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.AddPage()

	pdf.SetFont("Arial", "B", 18)
	pdf.CellFormat(0, 10, "Kumbh Tent Booking", "", 1, "L", false, 0, "")
	pdf.SetFont("Arial", "", 11)
	pdf.CellFormat(0, 6, "Tax Invoice", "", 1, "L", false, 0, "")
	pdf.Ln(4)

	pdf.SetFont("Arial", "B", 11)
	pdf.CellFormat(95, 6, "Invoice No: "+inv.InvoiceNumber, "", 0, "L", false, 0, "")
	pdf.CellFormat(95, 6, "Date: "+inv.CreatedAt, "", 1, "L", false, 0, "")
	pdf.Ln(4)

	pdf.SetFont("Arial", "B", 10)
	pdf.CellFormat(0, 6, "Bill To", "", 1, "L", false, 0, "")
	pdf.SetFont("Arial", "", 10)
	pdf.CellFormat(0, 5, inv.CustomerName, "", 1, "L", false, 0, "")
	pdf.CellFormat(0, 5, inv.CustomerPhone, "", 1, "L", false, 0, "")
	pdf.CellFormat(0, 5, inv.BillingCountry, "", 1, "L", false, 0, "")
	pdf.Ln(6)

	pdf.SetFillColor(240, 240, 240)
	pdf.SetFont("Arial", "B", 9)
	pdf.CellFormat(80, 8, "Description", "1", 0, "L", true, 0, "")
	pdf.CellFormat(38, 8, "Check-in", "1", 0, "C", true, 0, "")
	pdf.CellFormat(38, 8, "Check-out", "1", 0, "C", true, 0, "")
	pdf.CellFormat(34, 8, "Amount", "1", 1, "R", true, 0, "")
	pdf.SetFont("Arial", "", 9)
	desc := inv.TentName
	if inv.Location != "" {
		desc += " (" + inv.Location + ")"
	}
	pdf.CellFormat(80, 8, desc, "1", 0, "L", false, 0, "")
	pdf.CellFormat(38, 8, inv.CheckIn, "1", 0, "C", false, 0, "")
	pdf.CellFormat(38, 8, inv.CheckOut, "1", 0, "C", false, 0, "")
	pdf.CellFormat(34, 8, fmt.Sprintf("%.2f", inv.BaseAmount), "1", 1, "R", false, 0, "")
	pdf.Ln(4)

	pdf.SetFont("Arial", "", 10)
	pdf.CellFormat(150, 6, "Taxable Value", "", 0, "R", false, 0, "")
	pdf.CellFormat(40, 6, fmt.Sprintf("%.2f", inv.BaseAmount), "", 1, "R", false, 0, "")
	pdf.CellFormat(150, 6, "GST", "", 0, "R", false, 0, "")
	pdf.CellFormat(40, 6, fmt.Sprintf("%.2f", inv.Tax), "", 1, "R", false, 0, "")
	pdf.SetFont("Arial", "B", 11)
	pdf.CellFormat(150, 7, fmt.Sprintf("Total (%s)", inv.Currency), "", 0, "R", false, 0, "")
	pdf.CellFormat(40, 7, fmt.Sprintf("%.2f", inv.TotalAmount), "", 1, "R", false, 0, "")

	if len(inv.Notes) > 0 {
		pdf.Ln(6)
		pdf.SetFont("Arial", "B", 10)
		pdf.CellFormat(0, 6, "Adjustments", "", 1, "L", false, 0, "")
		pdf.SetFont("Arial", "", 9)
		for _, n := range inv.Notes {
			sign := "+"
			if n.NoteType == "credit" {
				sign = "-"
			}
			pdf.CellFormat(0, 5, fmt.Sprintf("%s (%s): %s%.2f — %s", n.NoteNumber, n.NoteType, sign, n.Amount, n.Reason), "", 1, "L", false, 0, "")
		}
		pdf.SetFont("Arial", "B", 10)
		pdf.CellFormat(150, 7, "Adjusted Total", "", 0, "R", false, 0, "")
		pdf.CellFormat(40, 7, fmt.Sprintf("%.2f", inv.AdjustedTotal), "", 1, "R", false, 0, "")
	}

	pdf.Ln(10)
	pdf.SetFont("Arial", "I", 8)
	pdf.CellFormat(0, 5, "Payment Status at Issue: "+inv.PaymentStatusAtIssue, "", 1, "L", false, 0, "")
	pdf.CellFormat(0, 5, "Booking Ref: "+inv.BookingRef, "", 1, "L", false, 0, "")

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// POST /admin/invoices/:id/email
func adminEmailInvoice(c *gin.Context) {
	inv, err := loadInvoiceDetail(c.Param("id"))
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "invoice not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch invoice"})
		return
	}

	var toEmail string
	db.QueryRow(`SELECT COALESCE(email,'') FROM users WHERE phone = $1`, inv.CustomerPhone).Scan(&toEmail)
	if toEmail == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "customer has no email address on file"})
		return
	}

	pdfBytes, err := buildInvoicePDF(inv)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate PDF"})
		return
	}

	subject := fmt.Sprintf("Invoice %s — Kumbh Tent Booking", inv.InvoiceNumber)
	body := fmt.Sprintf(
		"<p>Namaste %s,</p><p>Please find attached your invoice <b>%s</b> for booking <b>%s</b>.</p>",
		inv.CustomerName, inv.InvoiceNumber, inv.BookingRef,
	)
	if err := sendEmailWithAttachment(toEmail, subject, body, pdfBytes, inv.InvoiceNumber+".pdf"); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send email: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Invoice emailed", "to": toEmail})
}

// sendEmailWithAttachment builds a multipart/mixed message with
// one PDF attachment and sends it via the same SMTP config the
// booking-confirmation mailer uses (see email.go).
func sendEmailWithAttachment(toEmail, subject, htmlBody string, attachment []byte, filename string) error {
	host := envStr("SMTP_HOST", "")
	username := envStr("SMTP_USER", "")
	password := envStr("SMTP_PASS", "")
	if host == "" || username == "" || password == "" {
		return fmt.Errorf("SMTP not configured")
	}
	port := envStr("SMTP_PORT", "587")
	fromEmail := envStr("SMTP_FROM_EMAIL", username)
	fromName := envStr("SMTP_FROM_NAME", "Kumbh Tent Booking")

	const boundary = "kumbh-invoice-boundary-7f3a"
	var buf bytes.Buffer
	buf.WriteString(fmt.Sprintf("From: %s <%s>\r\n", fromName, fromEmail))
	buf.WriteString(fmt.Sprintf("To: %s\r\n", toEmail))
	buf.WriteString(fmt.Sprintf("Subject: %s\r\n", subject))
	buf.WriteString("MIME-Version: 1.0\r\n")
	buf.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n\r\n", boundary))

	buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
	buf.WriteString("Content-Type: text/html; charset=UTF-8\r\n\r\n")
	buf.WriteString(htmlBody + "\r\n\r\n")

	buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
	buf.WriteString("Content-Type: application/pdf\r\n")
	buf.WriteString("Content-Transfer-Encoding: base64\r\n")
	buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n\r\n", filename))
	encoded := base64.StdEncoding.EncodeToString(attachment)
	for i := 0; i < len(encoded); i += 76 {
		end := i + 76
		if end > len(encoded) {
			end = len(encoded)
		}
		buf.WriteString(encoded[i:end] + "\r\n")
	}
	buf.WriteString(fmt.Sprintf("\r\n--%s--\r\n", boundary))

	addr := host + ":" + port
	auth := smtp.PlainAuth("", username, password, host)
	return smtp.SendMail(addr, auth, fromEmail, []string{toEmail}, buf.Bytes())
}

// ── Credit / Debit Notes ──────────────────────────────────

func issueNote(c *gin.Context, noteType string) {
	invoiceIDStr := c.Param("id")
	invoiceID, err := strconv.Atoi(invoiceIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invoice id"})
		return
	}

	var body struct {
		Amount   float64 `json:"amount" binding:"required"`
		Reason   string  `json:"reason" binding:"required"`
		IssuedBy string  `json:"issued_by" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if body.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "amount must be positive"})
		return
	}
	if strings.TrimSpace(body.Reason) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason is required"})
		return
	}

	var exists bool
	db.QueryRow(`SELECT EXISTS(SELECT 1 FROM invoices WHERE id = $1)`, invoiceID).Scan(&exists)
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "invoice not found"})
		return
	}

	var seq int
	if err := db.QueryRow(`SELECT nextval('note_number_seq')`).Scan(&seq); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to allocate note number"})
		return
	}
	prefix := "CN"
	if noteType == "debit" {
		prefix = "DN"
	}
	noteNumber := fmt.Sprintf("%s-2027-%05d", prefix, seq)

	var id int
	err = db.QueryRow(`
		INSERT INTO credit_debit_notes (note_number, invoice_id, note_type, amount, reason, issued_by)
		VALUES ($1,$2,$3,$4,$5,$6)
		RETURNING id
	`, noteNumber, invoiceID, noteType, body.Amount, strings.TrimSpace(body.Reason), strings.TrimSpace(body.IssuedBy)).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue note: " + err.Error()})
		return
	}

	noteTypeLabel := "Credit"
	if noteType == "debit" {
		noteTypeLabel = "Debit"
	}
	inv, _ := loadInvoiceDetail(invoiceIDStr)
	resp := gin.H{
		"message":     fmt.Sprintf("%s note issued", noteTypeLabel),
		"note_number": noteNumber,
		"id":          id,
	}
	if inv != nil {
		resp["adjusted_total"] = inv.AdjustedTotal
	}
	c.JSON(http.StatusCreated, resp)
}

// POST /admin/invoices/:id/credit-note
func adminIssueCreditNote(c *gin.Context) { issueNote(c, "credit") }

// POST /admin/invoices/:id/debit-note
func adminIssueDebitNote(c *gin.Context) { issueNote(c, "debit") }

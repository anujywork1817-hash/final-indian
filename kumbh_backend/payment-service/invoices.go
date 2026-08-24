package main

import "fmt"

// ── Invoice generation (online-payment path) ─────────────
//
// Mirrors booking-service/invoices.go's generateInvoiceForBooking
// — this codebase duplicates small per-service helpers rather
// than sharing a package (see sendFCMNotification, email.go).
// This copy is simpler because verifyPayment already guarantees
// the full amount was just captured with no refund possible yet,
// so payment_status_at_issue is always "Paid" here — the fuller
// Paid/Partial/Pending/Refunded logic in booking-service's
// paymentStatusFor is only needed for the cash-confirmation path,
// which doesn't have that guarantee.
func generateInvoiceForBooking(
	bookingRef, phone, tentName, location, currency,
	checkIn, checkOut, guestName string,
	baseAmount, discount, tax, totalAmount float64,
) {
	var country string
	db.QueryRow(`SELECT COALESCE(country,'India') FROM users WHERE phone = $1`, phone).Scan(&country)
	if country == "" {
		country = "India"
	}

	customerName := guestName
	if customerName == "" {
		customerName = phone
	}

	var invoiceSeq int
	if err := db.QueryRow(`SELECT nextval('invoice_number_seq')`).Scan(&invoiceSeq); err != nil {
		fmt.Printf("⚠️  invoice: could not allocate invoice number for %s: %v\n", bookingRef, err)
		return
	}
	invoiceNumber := fmt.Sprintf("INV-2027-%05d", invoiceSeq)

	_, err := db.Exec(`
		INSERT INTO invoices
			(invoice_number, booking_ref, customer_name, customer_phone, billing_country,
			 tent_name, location, check_in, check_out, base_amount, tax, total_amount,
			 currency, payment_status_at_issue)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'Paid')
		ON CONFLICT (booking_ref) DO NOTHING
	`, invoiceNumber, bookingRef, customerName, phone, country,
		tentName, location, checkIn, checkOut, baseAmount-discount, tax, totalAmount, currency,
	)
	if err != nil {
		fmt.Printf("⚠️  invoice: could not create invoice for %s: %v\n", bookingRef, err)
		return
	}
	fmt.Printf("🧾 invoice %s generated for booking %s\n", invoiceNumber, bookingRef)
}

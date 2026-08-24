package main

import (
	"fmt"
	"net/smtp"
	"time"
)

// ── Booking confirmation email ───────────────────────────
//
// Mirrors payment-service/email.go (each service is a standalone
// binary in this codebase — see sendFCMNotification, duplicated
// the same way — so the mailer is duplicated here too rather
// than factored into a shared module).
//
// booking-service's own trigger is adminUpdateBookingStatus
// moving a booking to 'confirmed', which happens for cash-at-
// the-tent payments; the Razorpay online-payment path is
// triggered from payment-service's verifyPayment instead.

// sendConfirmationEmailForBooking looks up everything needed and
// sends the confirmation email for one booking ref. Never blocks
// or fails the caller — always run via `go`.
func sendConfirmationEmailForBooking(bookingRef string) {
	var (
		phone, tentName, location string
		checkInTime, checkOutTime time.Time
		nights, guests            int
		guestName                 string
		totalAmount               float64
	)
	err := db.QueryRow(`
		SELECT phone, tent_name, COALESCE(location,''),
		       check_in, check_out, nights, guests,
		       COALESCE(guest_name,''), total_amount
		FROM bookings WHERE booking_ref = $1
	`, bookingRef).Scan(
		&phone, &tentName, &location,
		&checkInTime, &checkOutTime, &nights, &guests,
		&guestName, &totalAmount,
	)
	if err != nil {
		fmt.Printf("⚠️  confirmation email: could not load booking %s: %v\n", bookingRef, err)
		return
	}
	checkInDate := checkInTime.Format("2 Jan 2006")
	checkOutDate := checkOutTime.Format("2 Jan 2006")

	var userEmail string
	if err := db.QueryRow(`
		SELECT COALESCE(email, '') FROM users WHERE phone = $1
	`, phone).Scan(&userEmail); err != nil || userEmail == "" {
		return
	}

	sendBookingConfirmationEmail(
		userEmail, guestName, bookingRef, tentName, location,
		checkInDate, checkOutDate, nights, guests, totalAmount,
	)
}

func sendBookingConfirmationEmail(
	toEmail, guestName, bookingRef, tentName, location,
	checkIn, checkOut string, nights, guests int, totalAmount float64,
) {
	if toEmail == "" {
		return
	}

	host := envStr("SMTP_HOST", "")
	username := envStr("SMTP_USER", "")
	password := envStr("SMTP_PASS", "")
	if host == "" || username == "" || password == "" {
		fmt.Println("✉️  SMTP not configured — skipping booking confirmation email")
		return
	}
	port := envStr("SMTP_PORT", "587")
	fromEmail := envStr("SMTP_FROM_EMAIL", username)
	fromName := envStr("SMTP_FROM_NAME", "Kumbh Tent Booking")

	if guestName == "" {
		guestName = "Guest"
	}

	subject := fmt.Sprintf("Booking Confirmed — %s (Ref: %s)", tentName, bookingRef)
	html := bookingConfirmationHTML(guestName, bookingRef, tentName, location,
		checkIn, checkOut, nights, guests, totalAmount)
	msg := buildConfirmationMIME(fromName, fromEmail, toEmail, subject, html)

	addr := host + ":" + port
	auth := smtp.PlainAuth("", username, password, host)

	if err := smtp.SendMail(addr, auth, fromEmail, []string{toEmail}, []byte(msg)); err != nil {
		fmt.Printf("⚠️  confirmation email to %s failed: %v\n", toEmail, err)
		return
	}
	fmt.Printf("✅ confirmation email sent to %s for booking %s\n", toEmail, bookingRef)
}

func buildConfirmationMIME(fromName, fromEmail, toEmail, subject, htmlBody string) string {
	return fmt.Sprintf(
		"From: %s <%s>\r\n"+
			"To: %s\r\n"+
			"Subject: %s\r\n"+
			"MIME-Version: 1.0\r\n"+
			"Content-Type: text/html; charset=UTF-8\r\n"+
			"\r\n%s\r\n",
		fromName, fromEmail, toEmail, subject, htmlBody,
	)
}

// bookingConfirmationHTML is the email body — inline-styled, so
// it renders the same across email clients that strip <style>
// blocks and ignore external CSS.
func bookingConfirmationHTML(
	guestName, bookingRef, tentName, location,
	checkIn, checkOut string, nights, guests int, totalAmount float64,
) string {
	return fmt.Sprintf(`<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#FFF3EA;font-family:Arial,Helvetica,sans-serif;">
  <table width="100%%" cellpadding="0" cellspacing="0" style="padding:24px 0;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #E8DCC8;">
        <tr>
          <td style="background:linear-gradient(135deg,#BF4E00,#F6720B);padding:24px;text-align:center;">
            <div style="font-size:28px;">⛺</div>
            <div style="color:#ffffff;font-size:20px;font-weight:700;margin-top:6px;">Booking Confirmed!</div>
            <div style="color:#FFE8D6;font-size:13px;margin-top:4px;">Nashik Kumbh 2027</div>
          </td>
        </tr>
        <tr>
          <td style="padding:24px;">
            <p style="font-size:15px;color:#2B2B2B;margin:0 0 12px;">
              Namaste %s,
            </p>
            <p style="font-size:14px;color:#5A4A3A;line-height:1.6;margin:0 0 20px;">
              Thank you for booking with Kumbh Tent. Your booking has been
              <b>confirmed</b> and payment received — we look forward to
              hosting you at the Simhastha Kumbh.
            </p>

            <table width="100%%" cellpadding="8" cellspacing="0" style="background:#FFF3EA;border-radius:10px;font-size:13px;color:#2B2B2B;">
              <tr><td style="color:#8A7D6B;">Booking Ref</td><td align="right"><b>%s</b></td></tr>
              <tr><td style="color:#8A7D6B;">Tent</td><td align="right"><b>%s</b></td></tr>
              <tr><td style="color:#8A7D6B;">Location</td><td align="right">%s</td></tr>
              <tr><td style="color:#8A7D6B;">Check-in</td><td align="right">%s</td></tr>
              <tr><td style="color:#8A7D6B;">Check-out</td><td align="right">%s</td></tr>
              <tr><td style="color:#8A7D6B;">Nights</td><td align="right">%d</td></tr>
              <tr><td style="color:#8A7D6B;">Guests</td><td align="right">%d</td></tr>
              <tr><td style="color:#8A7D6B;font-weight:700;padding-top:10px;">Total Paid</td>
                  <td align="right" style="font-weight:800;color:#BF4E00;padding-top:10px;">₹%.2f</td></tr>
            </table>

            <p style="font-size:12px;color:#8A7D6B;line-height:1.6;margin:20px 0 0;">
              Open the Kumbh Tent app and go to <b>My Bookings</b> to view your
              QR e-ticket — show it at the camp entrance for check-in.
            </p>
          </td>
        </tr>
        <tr>
          <td style="background:#FFF3EA;padding:14px;text-align:center;font-size:11px;color:#8A7D6B;">
            ⛺ Kumbh Tent Booking &middot; Nashik Kumbh 2027
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`,
		guestName, bookingRef, tentName, location,
		checkIn, checkOut, nights, guests, totalAmount,
	)
}

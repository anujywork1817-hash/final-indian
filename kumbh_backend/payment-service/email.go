package main

import (
	"fmt"
	"net/smtp"
	"os"
)

// ── Booking confirmation email ───────────────────────────
//
// Sent once payment is verified and a booking moves to
// 'confirmed' — the same trigger point as the existing FCM push
// in verifyPayment. Uses plain net/smtp (stdlib only): most
// providers, including Gmail, accept STARTTLS on port 587, which
// smtp.SendMail negotiates automatically when the server offers
// it.
//
// Must never block or fail the payment flow: every error is
// logged and swallowed, exactly like sendFCMNotification above.
func sendBookingConfirmationEmail(
	toEmail, guestName, bookingRef, tentName, location,
	checkIn, checkOut string, nights, guests int, totalAmount float64,
) {
	if toEmail == "" {
		return
	}

	host := os.Getenv("SMTP_HOST")
	username := os.Getenv("SMTP_USER")
	password := os.Getenv("SMTP_PASS")
	if host == "" || username == "" || password == "" {
		fmt.Println("✉️  SMTP not configured — skipping booking confirmation email")
		return
	}
	port := emailEnvDefault("SMTP_PORT", "587")
	fromEmail := emailEnvDefault("SMTP_FROM_EMAIL", username)
	fromName := emailEnvDefault("SMTP_FROM_NAME", "Kumbh Tent Booking")

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

func emailEnvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
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

// bookingConfirmationHTML is the email body — a simple, inline-
// styled ticket summary (email clients strip <style> blocks and
// ignore external CSS, so everything here is inline).
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

package main

import "testing"

func TestPaymentStatusFor(t *testing.T) {
	cases := []struct {
		name                  string
		bookingStatus         string
		total, paid, refunded int64
		want                  string
	}{
		{"unpaid pending booking", "pending", 100000, 0, 0, "Pending"},
		{"fully paid confirmed booking", "confirmed", 100000, 100000, 0, "Paid"},
		{"partial cash payment", "confirmed", 100000, 40000, 0, "Partial"},
		{"one paisa short still partial", "confirmed", 100000, 99999, 0, "Partial"},
		{"cancelled with a settled refund", "cancelled", 100000, 100000, 100000, "Refunded"},
		{"cancelled with no refund yet processed", "cancelled", 100000, 100000, 0, "Cancelled"},
		{"no_show with partial refund settled", "no_show", 100000, 100000, 40000, "Refunded"},
		{"no_show, refund still pending (not yet succeeded)", "no_show", 100000, 100000, 0, "Cancelled"},
		{"paid exactly matches total", "confirmed", 50000, 50000, 0, "Paid"},
		{"overpaid (defensive — should still read Paid, never a new state)", "confirmed", 50000, 60000, 0, "Paid"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := paymentStatusFor(tc.bookingStatus, tc.total, tc.paid, tc.refunded)
			if got != tc.want {
				t.Errorf("paymentStatusFor(%q, %d, %d, %d) = %q, want %q",
					tc.bookingStatus, tc.total, tc.paid, tc.refunded, got, tc.want)
			}
		})
	}
}

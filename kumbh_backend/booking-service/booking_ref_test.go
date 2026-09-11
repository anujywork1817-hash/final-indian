package main

import (
	"errors"
	"regexp"
	"testing"

	"github.com/lib/pq"
)

// BUG: booking-ref retry. newBookingRef must produce refs in the
// expected shape and with enough entropy that createBooking's retry
// loop (bounded at 5 attempts) essentially never exhausts itself.
func TestNewBookingRefFormat(t *testing.T) {
	re := regexp.MustCompile(`^KTB-2027-\d{7}$`)
	seen := map[string]bool{}
	for i := 0; i < 500; i++ {
		ref := newBookingRef()
		if !re.MatchString(ref) {
			t.Fatalf("newBookingRef() = %q, want to match %s", ref, re.String())
		}
		seen[ref] = true
	}
	// 500 draws from a 10,000,000-value space should essentially
	// never collide; if this fails, the RNG is broken (e.g. always
	// returning 0).
	if len(seen) < 495 {
		t.Errorf("only %d unique refs out of 500 draws — RNG looks degenerate", len(seen))
	}
}

// BUG-27: isUniqueViolation must recognize a Postgres unique-key
// violation on the named constraint and ignore everything else, so
// createBooking's retry only fires for an actual booking_ref
// collision and payment-service's duplicate-payment guard only fires
// for an actual razorpay_payment collision.
func TestIsUniqueViolation(t *testing.T) {
	violation := &pq.Error{Code: "23505", Constraint: "bookings_booking_ref_key"}
	otherViolation := &pq.Error{Code: "23505", Constraint: "some_other_key"}
	notAViolation := &pq.Error{Code: "23503", Constraint: "bookings_booking_ref_key"}
	plainErr := errors.New("connection reset")

	cases := []struct {
		name       string
		err        error
		constraint string
		want       bool
	}{
		{"matching unique violation", violation, "booking_ref", true},
		{"empty constraint filter matches any unique violation", violation, "", true},
		{"unique violation on a different constraint", otherViolation, "booking_ref", false},
		{"non-unique-violation pq error", notAViolation, "booking_ref", false},
		{"non-pq error", plainErr, "booking_ref", false},
		{"nil error", nil, "booking_ref", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isUniqueViolation(tc.err, tc.constraint); got != tc.want {
				t.Errorf("isUniqueViolation(%v, %q) = %v, want %v", tc.err, tc.constraint, got, tc.want)
			}
		})
	}
}

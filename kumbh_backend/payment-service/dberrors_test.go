package main

import (
	"errors"
	"testing"

	"github.com/lib/pq"
)

// BUG-27: verifyPayment relies on this to tell a genuine duplicate
// (same Razorpay payment verified twice — migrations/016 makes that
// a unique-key violation) apart from any other INSERT failure, which
// must still surface as a 500.
func TestIsUniqueViolation(t *testing.T) {
	violation := &pq.Error{Code: "23505", Constraint: "uq_payments_razorpay_payment_success"}
	otherViolation := &pq.Error{Code: "23505", Constraint: "some_other_key"}
	notAViolation := &pq.Error{Code: "23503", Constraint: "uq_payments_razorpay_payment_success"}
	plainErr := errors.New("connection reset")

	cases := []struct {
		name       string
		err        error
		constraint string
		want       bool
	}{
		{"matching unique violation", violation, "razorpay_payment", true},
		{"empty constraint filter matches any unique violation", violation, "", true},
		{"unique violation on a different constraint", otherViolation, "razorpay_payment", false},
		{"non-unique-violation pq error", notAViolation, "razorpay_payment", false},
		{"non-pq error", plainErr, "razorpay_payment", false},
		{"nil error", nil, "razorpay_payment", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isUniqueViolation(tc.err, tc.constraint); got != tc.want {
				t.Errorf("isUniqueViolation(%v, %q) = %v, want %v", tc.err, tc.constraint, got, tc.want)
			}
		})
	}
}

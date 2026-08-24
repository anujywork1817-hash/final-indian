package main

import (
	"testing"
	"time"
)

// stdCheckIn is fixed; cancellation timestamps are derived by
// subtracting/adding notice, matching the style already used in
// refund_policy_test.go.
var stdCheckIn = time.Date(2027, 1, 20, 12, 0, 0, 0, time.UTC)

func stdBefore(hours float64) time.Time {
	return stdCheckIn.Add(-time.Duration(hours * float64(time.Hour)))
}

func stdAfter(hours float64) time.Time {
	return stdCheckIn.Add(time.Duration(hours * float64(time.Hour)))
}

// stdPolicy: free >=168h (7 days), partial penalty 30% between
// 168h and 24h notice, one-night penalty below 24h. Night price
// is a fifth of the total paid, for a clean assertion.
var stdPolicy = CancellationPolicyConfig{
	PolicyType:                  PolicyFreeCancellation,
	FreeCancellationHours:       168,
	PartialRefundPenaltyPercent: 30,
	LateCancellationHours:       24,
	NoShowCutoffHours:           6,
	NoShowPenaltyPercent:        100,
}

func stdBooking(paidPaise int64, checkIn time.Time, status string) BookingForRefund {
	return BookingForRefund{
		BookingRef: "KTB-TEST-00001",
		PaidPaise:  paidPaise,
		NightPaise: paidPaise / 5,
		CheckIn:    checkIn,
		Status:     status,
		Policy:     stdPolicy,
	}
}

// ── Tier 1: FREE_CANCELLATION ─────────────────────────────

func TestFreeCancellation_WellBeforeDeadline(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(1000))
	if r.TierApplied != TierFreeCancellation {
		t.Fatalf("tier = %s, want FREE_CANCELLATION", r.TierApplied)
	}
	if r.RefundAmountPaise != 500000 {
		t.Errorf("refund = %d, want 500000 (full)", r.RefundAmountPaise)
	}
	if r.PenaltyAmountPaise != 0 {
		t.Errorf("penalty = %d, want 0", r.PenaltyAmountPaise)
	}
	if r.RefundPercent != 100 {
		t.Errorf("percent = %v, want 100", r.RefundPercent)
	}
}

func TestFreeCancellation_ExactlyAtDeadline(t *testing.T) {
	// Exactly 168h notice: the deadline boundary is inclusive —
	// still free. This is the documented assumption; see the
	// summary sent to the user.
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(168))
	if r.TierApplied != TierFreeCancellation {
		t.Fatalf("tier = %s, want FREE_CANCELLATION at exact deadline", r.TierApplied)
	}
	if r.RefundAmountPaise != 500000 {
		t.Errorf("refund = %d, want 500000", r.RefundAmountPaise)
	}
}

func TestFreeCancellation_OneSecondBeforeDeadlinePasses(t *testing.T) {
	// 168h + 1s notice: still comfortably inside the free window.
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(168).Add(-1*time.Second))
	if r.TierApplied != TierFreeCancellation {
		t.Fatalf("tier = %s, want FREE_CANCELLATION", r.TierApplied)
	}
}

// ── Tier 2: PARTIAL_REFUND ────────────────────────────────

func TestPartialRefund_OneSecondAfterFreeDeadline(t *testing.T) {
	// 168h - 1s notice: just crossed out of the free window.
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(168).Add(1*time.Second))
	if r.TierApplied != TierPartialRefund {
		t.Fatalf("tier = %s, want PARTIAL_REFUND", r.TierApplied)
	}
	wantPenalty := int64(150000) // 30% of 500000
	if r.PenaltyAmountPaise != wantPenalty {
		t.Errorf("penalty = %d, want %d", r.PenaltyAmountPaise, wantPenalty)
	}
	if r.RefundAmountPaise != 350000 {
		t.Errorf("refund = %d, want 350000", r.RefundAmountPaise)
	}
}

func TestPartialRefund_MidWindow(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(96))
	if r.TierApplied != TierPartialRefund {
		t.Fatalf("tier = %s, want PARTIAL_REFUND", r.TierApplied)
	}
	if r.RefundAmountPaise != 350000 {
		t.Errorf("refund = %d, want 350000", r.RefundAmountPaise)
	}
}

func TestPartialRefund_ExactlyAtLateCutoff(t *testing.T) {
	// Exactly 24h notice: the late-cancellation boundary is also
	// inclusive on the more generous side — still PARTIAL_REFUND,
	// not yet ONE_NIGHT_PENALTY.
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(24))
	if r.TierApplied != TierPartialRefund {
		t.Fatalf("tier = %s, want PARTIAL_REFUND at exact late cutoff", r.TierApplied)
	}
}

// ── Tier 3: ONE_NIGHT_PENALTY ──────────────────────────────

func TestOneNightPenalty_OneSecondAfterLateCutoff(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(24).Add(1*time.Second))
	if r.TierApplied != TierOneNightPenalty {
		t.Fatalf("tier = %s, want ONE_NIGHT_PENALTY", r.TierApplied)
	}
	wantPenalty := int64(100000) // NightPaise = paid/5
	if r.PenaltyAmountPaise != wantPenalty {
		t.Errorf("penalty = %d, want %d", r.PenaltyAmountPaise, wantPenalty)
	}
	if r.RefundAmountPaise != 400000 {
		t.Errorf("refund = %d, want 400000", r.RefundAmountPaise)
	}
}

func TestOneNightPenalty_JustBeforeCheckIn(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdBefore(0.001))
	if r.TierApplied != TierOneNightPenalty {
		t.Fatalf("tier = %s, want ONE_NIGHT_PENALTY", r.TierApplied)
	}
}

func TestOneNightPenalty_NightPriceExceedsPaidAmount(t *testing.T) {
	// Defensive: if NightPaise is misconfigured above what was
	// actually paid, never refund a negative amount.
	b := stdBooking(500000, stdCheckIn, "confirmed")
	b.NightPaise = 900000
	r := calculateRefund(b, stdBefore(1))
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0 (penalty capped at paid amount)", r.RefundAmountPaise)
	}
	if r.PenaltyAmountPaise != 500000 {
		t.Errorf("penalty = %d, want 500000 (capped)", r.PenaltyAmountPaise)
	}
}

// ── Edge case: cancellation after check-in has already begun ─

func TestCancellationAfterCheckInStarted(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdAfter(3))
	if r.TierApplied != TierOneNightPenalty {
		t.Fatalf("tier = %s, want ONE_NIGHT_PENALTY for cancellation after check-in", r.TierApplied)
	}
	if r.RefundAmountPaise != 400000 {
		t.Errorf("refund = %d, want 400000", r.RefundAmountPaise)
	}
}

func TestCancellationWellAfterCheckIn(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	r := calculateRefund(b, stdAfter(72))
	if r.TierApplied != TierOneNightPenalty {
		t.Fatalf("tier = %s, want ONE_NIGHT_PENALTY", r.TierApplied)
	}
}

// ── Tier 4: NON_REFUNDABLE ────────────────────────────────

func TestNonRefundable_OverridesEvenWellBeforeDeadline(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	b.Policy.PolicyType = PolicyNonRefundable
	r := calculateRefund(b, stdBefore(1000))
	if r.TierApplied != TierNonRefundable {
		t.Fatalf("tier = %s, want NON_REFUNDABLE", r.TierApplied)
	}
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0", r.RefundAmountPaise)
	}
	if r.PenaltyAmountPaise != 500000 {
		t.Errorf("penalty = %d, want 500000 (entire paid amount)", r.PenaltyAmountPaise)
	}
}

func TestNonRefundable_AfterCheckIn(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	b.Policy.PolicyType = PolicyNonRefundable
	r := calculateRefund(b, stdAfter(10))
	if r.TierApplied != TierNonRefundable || r.RefundAmountPaise != 0 {
		t.Fatalf("non-refundable must yield zero refund at any time, got tier=%s refund=%d", r.TierApplied, r.RefundAmountPaise)
	}
}

// ── Tier 5: NO_SHOW ────────────────────────────────────────

func TestNoShow_FullPenalty(t *testing.T) {
	r := calculateNoShowRefund(500000, stdPolicy)
	if r.TierApplied != TierNoShow {
		t.Fatalf("tier = %s, want NO_SHOW", r.TierApplied)
	}
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0 (policy no-show penalty is 100%%)", r.RefundAmountPaise)
	}
	if r.PenaltyAmountPaise != 500000 {
		t.Errorf("penalty = %d, want 500000", r.PenaltyAmountPaise)
	}
}

func TestNoShow_PartialPenalty(t *testing.T) {
	p := stdPolicy
	p.NoShowPenaltyPercent = 50
	r := calculateNoShowRefund(500000, p)
	if r.RefundAmountPaise != 250000 {
		t.Errorf("refund = %d, want 250000", r.RefundAmountPaise)
	}
	if r.PenaltyAmountPaise != 250000 {
		t.Errorf("penalty = %d, want 250000", r.PenaltyAmountPaise)
	}
}

func TestNoShow_NothingPaid(t *testing.T) {
	r := calculateNoShowRefund(0, stdPolicy)
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0", r.RefundAmountPaise)
	}
}

// ── Already cancelled / already refunded / not cancellable ──

func TestAlreadyCancelled(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "cancelled")
	r := calculateRefund(b, stdBefore(500))
	if r.TierApplied != TierAlreadyCancelled {
		t.Fatalf("tier = %s, want ALREADY_CANCELLED", r.TierApplied)
	}
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0 — must not compute a fresh quote for an already-cancelled booking", r.RefundAmountPaise)
	}
}

func TestAlreadyMarkedNoShow(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "no_show")
	r := calculateRefund(b, stdAfter(10))
	if r.TierApplied != TierAlreadyCancelled {
		t.Fatalf("tier = %s, want ALREADY_CANCELLED for a booking already marked no_show", r.TierApplied)
	}
}

func TestCompletedBookingNotCancellable(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "completed")
	r := calculateRefund(b, stdBefore(1))
	if r.TierApplied != TierNotCancellable {
		t.Fatalf("tier = %s, want NOT_CANCELLABLE", r.TierApplied)
	}
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0", r.RefundAmountPaise)
	}
}

func TestAlreadyRefundedBookingYieldsNoSecondQuote(t *testing.T) {
	b := stdBooking(500000, stdCheckIn, "confirmed")
	b.AlreadyRefunded = true
	r := calculateRefund(b, stdBefore(500))
	if r.TierApplied != TierAlreadyRefunded {
		t.Fatalf("tier = %s, want ALREADY_REFUNDED", r.TierApplied)
	}
	if r.RefundAmountPaise != 0 {
		t.Errorf("refund = %d, want 0 — must never compute a second refund", r.RefundAmountPaise)
	}
}

func TestNothingPaidYieldsNotCancellable(t *testing.T) {
	b := stdBooking(0, stdCheckIn, "pending")
	r := calculateRefund(b, stdBefore(500))
	if r.TierApplied != TierNotCancellable {
		t.Fatalf("tier = %s, want NOT_CANCELLABLE for an unpaid booking", r.TierApplied)
	}
}

// ── Invariants, swept across the whole boundary space ────────
//
// Mirrors the exhaustive sweep style already used for the
// hours:percent policy in refund_policy_test.go: whatever the
// notice given, a refund must never be negative, never exceed
// what was paid, and refund+penalty must never exceed paid.

func TestInvariants_NeverNegativeNeverExceedsPaid(t *testing.T) {
	paid := int64(773300) // an odd, non-round amount on purpose
	notices := []float64{
		-1000, -100, -24.001, -24, -1, -0.001, 0, 0.001, 1,
		23.999, 24, 24.001, 100, 167.999, 168, 168.001, 1000,
	}
	for _, n := range notices {
		b := stdBooking(paid, stdCheckIn, "confirmed")
		r := calculateRefund(b, stdBefore(n))
		if r.RefundAmountPaise < 0 {
			t.Errorf("notice=%vh: refund %d is negative", n, r.RefundAmountPaise)
		}
		if r.RefundAmountPaise > paid {
			t.Errorf("notice=%vh: refund %d exceeds paid %d", n, r.RefundAmountPaise, paid)
		}
		if r.RefundAmountPaise+r.PenaltyAmountPaise != paid {
			t.Errorf("notice=%vh: refund(%d) + penalty(%d) != paid(%d)",
				n, r.RefundAmountPaise, r.PenaltyAmountPaise, paid)
		}
	}
}

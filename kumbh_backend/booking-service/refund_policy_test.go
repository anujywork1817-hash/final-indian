package main

import (
	"testing"
	"time"
)

// checkIn is fixed; `now` is derived by subtracting notice.
var checkIn = time.Date(2027, 1, 20, 12, 0, 0, 0, time.UTC)

func at(noticeHours float64) time.Time {
	return checkIn.Add(-time.Duration(noticeHours * float64(time.Hour)))
}

// tcPolicy mirrors the cancellation policy published in the
// app's own Terms & Conditions screen (terms_screen.dart):
// 7+ days → 80%, 3-6 days → 50%, within 48h → nothing.
var tcPolicy = RefundPolicy{
	Enabled: true,
	Tiers:   parseRefundTiers("168:80,72:50,0:0"),
}

// defaultPolicy is what ships out of the box: full refund.
var defaultPolicy = RefundPolicy{Enabled: true}

func TestDefaultPolicyRefundsEverything(t *testing.T) {
	cases := []float64{0, 1, 47, 48, 72, 168, 1000}
	for _, notice := range cases {
		q := defaultPolicy.Quote(500000, at(notice), checkIn)
		if q.RefundPaise != 500000 {
			t.Errorf("notice=%vh: got %d paise, want 500000", notice, q.RefundPaise)
		}
		if q.FeePaise != 0 {
			t.Errorf("notice=%vh: got fee %d, want 0", notice, q.FeePaise)
		}
		if q.Rule != "full_refund" {
			t.Errorf("notice=%vh: got rule %q, want full_refund", notice, q.Rule)
		}
	}
}

// Default policy must refund even after check-in has passed —
// it is the "never under-refund" default the business chose.
func TestDefaultPolicyRefundsAfterCheckInPassed(t *testing.T) {
	q := defaultPolicy.Quote(500000, checkIn.Add(48*time.Hour), checkIn)
	if q.RefundPaise != 500000 {
		t.Errorf("got %d, want full 500000 even post-check-in", q.RefundPaise)
	}
}

// ── Tier boundaries ──────────────────────────────────────
// The exact hour a tier flips is where money is won or lost,
// so every boundary is pinned from both sides.

func TestTierBoundaries(t *testing.T) {
	const amount = 1000000 // ₹10,000

	tests := []struct {
		name   string
		notice float64
		want   int64
		pct    float64
	}{
		{"well beyond top tier", 720, 800000, 80},  // 30 days
		{"exactly 168h (7 days)", 168, 800000, 80}, // boundary, inclusive
		{"one minute under 168h", 167.99, 500000, 50},
		{"167h falls to middle tier", 167, 500000, 50},
		{"exactly 72h (3 days)", 72, 500000, 50}, // boundary, inclusive
		{"one minute under 72h", 71.99, 0, 0},
		{"48h is inside no-refund window", 48, 0, 0},
		{"1h notice", 1, 0, 0},
		{"exactly at check-in", 0, 0, 0},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			q := tcPolicy.Quote(amount, at(tc.notice), checkIn)
			if q.RefundPaise != tc.want {
				t.Errorf("notice=%vh: got %d paise, want %d", tc.notice, q.RefundPaise, tc.want)
			}
			if q.Percent != tc.pct {
				t.Errorf("notice=%vh: got %g%%, want %g%%", tc.notice, q.Percent, tc.pct)
			}
		})
	}
}

// Cancelling AFTER check-in must not match a >=0h tier by
// accident via negative-hour arithmetic.
func TestTieredPolicyAfterCheckIn(t *testing.T) {
	q := tcPolicy.Quote(1000000, checkIn.Add(24*time.Hour), checkIn)
	if q.RefundPaise != 0 {
		t.Errorf("got %d, want 0 for post-check-in cancellation", q.RefundPaise)
	}
}

// ── Rounding ─────────────────────────────────────────────

func TestRoundingIsHalfUpAndNeverOverRefunds(t *testing.T) {
	tests := []struct {
		name    string
		paise   int64
		percent float64
		want    int64
	}{
		// 101 * 50% = 50.5 → half-up → 51
		{"half rounds up", 101, 50, 51},
		// 103 * 50% = 51.5 → half-up → 52
		{"half rounds up again", 103, 50, 52},
		// 100 * 33.333% = 33.333 → 33
		{"rounds down below half", 100, 33.333, 33},
		// 3 * 50% = 1.5 → 2
		{"tiny amount", 3, 50, 2},
		{"one paise at 50pct", 1, 50, 1}, // 0.5 → half-up → 1
		{"zero percent", 999999, 0, 0},
		{"hundred percent is exact", 123457, 100, 123457},
		{"zero amount", 0, 80, 0},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := applyPercent(tc.paise, tc.percent)
			if got != tc.want {
				t.Errorf("applyPercent(%d, %g) = %d, want %d", tc.paise, tc.percent, got, tc.want)
			}
			if got > tc.paise {
				t.Errorf("applyPercent(%d, %g) = %d exceeds principal", tc.paise, tc.percent, got)
			}
		})
	}
}

// An odd amount at 80% is the classic place a rounding bug
// hides. ₹1,234.57 → 123457 paise → 80% = 98765.6 → 98766.
func TestOddAmountTierRounding(t *testing.T) {
	q := tcPolicy.Quote(123457, at(200), checkIn)
	if q.RefundPaise != 98766 {
		t.Errorf("got %d paise, want 98766", q.RefundPaise)
	}
	if q.RefundRupees() != 987.66 {
		t.Errorf("got ₹%.2f, want ₹987.66", q.RefundRupees())
	}
}

// ── Processing fee ───────────────────────────────────────

func TestFeeIsDeductedFromGrossRefund(t *testing.T) {
	p := RefundPolicy{Enabled: true, FeePercent: 10}
	q := p.Quote(100000, at(500), checkIn) // ₹1000, full tier

	if q.FeePaise != 10000 {
		t.Errorf("fee = %d, want 10000", q.FeePaise)
	}
	if q.RefundPaise != 90000 {
		t.Errorf("refund = %d, want 90000", q.RefundPaise)
	}
}

func TestFeeStacksOnTopOfTier(t *testing.T) {
	p := RefundPolicy{Enabled: true, FeePercent: 10, Tiers: parseRefundTiers("168:80")}
	// 100000 * 80% = 80000 gross; 10% fee = 8000; net 72000.
	q := p.Quote(100000, at(200), checkIn)

	if q.RefundPaise != 72000 {
		t.Errorf("refund = %d, want 72000", q.RefundPaise)
	}
	if q.FeePaise != 8000 {
		t.Errorf("fee = %d, want 8000", q.FeePaise)
	}
}

// A 100% fee must floor at zero, never go negative.
func TestFullFeeNeverGoesNegative(t *testing.T) {
	p := RefundPolicy{Enabled: true, FeePercent: 100}
	q := p.Quote(100000, at(500), checkIn)

	if q.RefundPaise != 0 {
		t.Errorf("refund = %d, want 0", q.RefundPaise)
	}
	if q.RefundPaise < 0 {
		t.Fatal("refund went negative")
	}
}

// ── The DB constraint invariant ──────────────────────────
// ck_refunds_amount_bounds requires refund + fee <= booking.
// If Quote can ever violate it, the INSERT throws at runtime.

func TestQuoteNeverViolatesDBConstraint(t *testing.T) {
	policies := []RefundPolicy{
		defaultPolicy,
		tcPolicy,
		{Enabled: true, FeePercent: 10},
		{Enabled: true, FeePercent: 33.333, Tiers: parseRefundTiers("168:80,72:50,0:0")},
		{Enabled: true, FeePercent: 100, Tiers: parseRefundTiers("24:99.999")},
		{Enabled: false},
	}
	amounts := []int64{0, 1, 3, 7, 99, 101, 12345, 123457, 999999999}
	notices := []float64{-100, 0, 0.5, 47.9, 48, 71.99, 72, 167.99, 168, 10000}

	for pi, p := range policies {
		for _, amt := range amounts {
			for _, n := range notices {
				q := p.Quote(amt, at(n), checkIn)

				if q.RefundPaise < 0 || q.FeePaise < 0 {
					t.Fatalf("policy %d amt=%d notice=%v: negative (refund=%d fee=%d)",
						pi, amt, n, q.RefundPaise, q.FeePaise)
				}
				if q.RefundPaise+q.FeePaise > amt {
					t.Fatalf("policy %d amt=%d notice=%v: refund+fee=%d exceeds booking %d",
						pi, amt, n, q.RefundPaise+q.FeePaise, amt)
				}
			}
		}
	}
}

// ── Disabled / nothing-paid short circuits ───────────────

func TestDisabledPolicyRefundsNothing(t *testing.T) {
	p := RefundPolicy{Enabled: false}
	q := p.Quote(500000, at(1000), checkIn)
	if q.RefundPaise != 0 {
		t.Errorf("got %d, want 0", q.RefundPaise)
	}
	if q.Rule != "refunds_disabled" {
		t.Errorf("got rule %q, want refunds_disabled", q.Rule)
	}
}

func TestNothingPaidYieldsNothingBack(t *testing.T) {
	q := defaultPolicy.Quote(0, at(1000), checkIn)
	if q.RefundPaise != 0 || q.Rule != "nothing_paid" {
		t.Errorf("got %d/%q, want 0/nothing_paid", q.RefundPaise, q.Rule)
	}
}

// ── Tier spec parsing ────────────────────────────────────

func TestParseRefundTiersSortsDescending(t *testing.T) {
	tiers := parseRefundTiers("0:0,168:80,72:50")
	want := []RefundTier{{168, 80}, {72, 50}, {0, 0}}

	if len(tiers) != len(want) {
		t.Fatalf("got %d tiers, want %d", len(tiers), len(want))
	}
	for i := range want {
		if tiers[i] != want[i] {
			t.Errorf("tier %d = %+v, want %+v", i, tiers[i], want[i])
		}
	}
}

func TestParseRefundTiersToleratesFormatting(t *testing.T) {
	tiers := parseRefundTiers("  168h : 80% , 72h:50 ")
	if len(tiers) != 2 || tiers[0] != (RefundTier{168, 80}) || tiers[1] != (RefundTier{72, 50}) {
		t.Errorf("got %+v, want [{168 80} {72 50}]", tiers)
	}
}

// A typo must not take the service down, and must not
// silently invent a tier.
func TestParseRefundTiersSkipsGarbage(t *testing.T) {
	tiers := parseRefundTiers("168:80,garbage,99:notanumber,-5:50,72:150,72:50")
	want := []RefundTier{{168, 80}, {72, 50}}

	if len(tiers) != len(want) {
		t.Fatalf("got %+v, want %+v", tiers, want)
	}
	for i := range want {
		if tiers[i] != want[i] {
			t.Errorf("tier %d = %+v, want %+v", i, tiers[i], want[i])
		}
	}
}

// Empty / fully-invalid spec must fall back to 100%, the
// customer-safe direction.
func TestParseRefundTiersEmptyMeansFullRefund(t *testing.T) {
	for _, spec := range []string{"", "   ", ",,,", "total garbage"} {
		if tiers := parseRefundTiers(spec); tiers != nil {
			t.Errorf("spec %q: got %+v, want nil (=100%%)", spec, tiers)
		}
	}
}

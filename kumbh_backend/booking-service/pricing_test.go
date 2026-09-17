package main

import (
	"math"
	"testing"
)

func approx(a, b float64) bool { return math.Abs(a-b) < 0.005 }

// BUG-03/04: the GST slab must be chosen from the per-unit-night
// tariff, never the aggregated stay total. A ₹2,000/night tent booked
// for 4 nights totals ₹8,000 (> ₹7,500) but must still be taxed at
// 12%, while a single ₹8,000/night night is taxed at 18%.
func TestGSTSlabUsesPerNightTariff(t *testing.T) {
	cases := []struct {
		name          string
		pricePerNight int
		nights        int
		units         int
		wantRate      float64
	}{
		{"2000/night x4 nights stays 12pct", 2000, 4, 1, 0.12},
		{"7500/night is the 12pct boundary", 7500, 1, 1, 0.12},
		{"8000/night x1 night is 18pct", 8000, 1, 1, 0.18},
		{"aggregate over 7500 via units stays 12pct", 5000, 1, 3, 0.12},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := computeBookingCharges(tc.pricePerNight, tc.nights, tc.units, 0, 0, "Single", 0)
			if got.GSTRate != tc.wantRate {
				t.Fatalf("GSTRate = %v, want %v", got.GSTRate, tc.wantRate)
			}
			wantTax := got.Taxable * tc.wantRate
			if !approx(got.Tax, wantTax) {
				t.Fatalf("Tax = %v, want %v", got.Tax, wantTax)
			}
		})
	}
}

func TestChargesBreakdown(t *testing.T) {
	// ₹2000/night x 4 nights x 2 units = ₹16,000 base.
	// Double bed: +20% => ₹3,200. Two children 5-12: 2 x ₹500 x 4 = ₹4,000.
	// Two children under 5: 2 x ₹250 x 4 = ₹2,000.
	// Subtotal ₹25,200. 10% coupon => -₹2,520 => taxable ₹22,680.
	// GST 12% (₹2000/night) => ₹2,721.60. Total ₹25,401.60.
	got := computeBookingCharges(2000, 4, 2, 2, 2, "Double", 0.10)

	checks := []struct {
		name string
		got  float64
		want float64
	}{
		{"base", got.Base, 16000},
		{"bed surcharge", got.BedSurcharge, 3200},
		{"child fee", got.ChildFee, 4000},
		{"child under-5 fee", got.ChildUnder5Fee, 2000},
		{"subtotal", got.Subtotal, 25200},
		{"discount", got.Discount, 2520},
		{"taxable", got.Taxable, 22680},
		{"tax", got.Tax, 2721.6},
		{"total", got.Total, 25401.6},
	}
	for _, c := range checks {
		if !approx(c.got, c.want) {
			t.Errorf("%s = %v, want %v", c.name, c.got, c.want)
		}
	}
}

func TestSingleBedNoSurchargeNegativeChildrenClamped(t *testing.T) {
	got := computeBookingCharges(3000, 2, 1, -5, -5, "Single", 0)
	if got.BedSurcharge != 0 {
		t.Errorf("single bed surcharge = %v, want 0", got.BedSurcharge)
	}
	if got.ChildFee != 0 {
		t.Errorf("negative children not clamped: child fee = %v", got.ChildFee)
	}
	if got.ChildUnder5Fee != 0 {
		t.Errorf("negative under-5 children not clamped: fee = %v", got.ChildUnder5Fee)
	}
	if !approx(got.Total, 6000*1.12) {
		t.Errorf("total = %v, want %v", got.Total, 6000*1.12)
	}
}

// A tampered client claiming more children than the booking form
// allows must still only be charged/counted for the capped amount,
// matching booking_form_screen.dart's _maxChildrenAbove5/
// _maxChildrenUnder5 = 2, for both age brackets.
func TestChildrenCappedAtTwo(t *testing.T) {
	uncapped := computeBookingCharges(2000, 2, 1, 5, 5, "Single", 0)
	capped := computeBookingCharges(2000, 2, 1, 2, 2, "Single", 0)
	if !approx(uncapped.ChildFee, capped.ChildFee) {
		t.Errorf("ChildFee for 5 children = %v, want capped to match 2 children (%v)", uncapped.ChildFee, capped.ChildFee)
	}
	if !approx(uncapped.ChildUnder5Fee, capped.ChildUnder5Fee) {
		t.Errorf("ChildUnder5Fee for 5 children = %v, want capped to match 2 children (%v)", uncapped.ChildUnder5Fee, capped.ChildUnder5Fee)
	}
	wantChildFee := 2 * childFeePerNight * 2 // 2 children x rate x 2 nights
	if !approx(uncapped.ChildFee, wantChildFee) {
		t.Errorf("ChildFee = %v, want %v", uncapped.ChildFee, wantChildFee)
	}
	wantChildUnder5Fee := 2 * childUnder5FeePerNight * 2
	if !approx(uncapped.ChildUnder5Fee, wantChildUnder5Fee) {
		t.Errorf("ChildUnder5Fee = %v, want %v", uncapped.ChildUnder5Fee, wantChildUnder5Fee)
	}
}

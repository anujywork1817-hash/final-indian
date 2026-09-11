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
			got := computeBookingCharges(tc.pricePerNight, tc.nights, tc.units, 0, "Single", 0)
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
	// Subtotal ₹23,200. 10% coupon => -₹2,320 => taxable ₹20,880.
	// GST 12% (₹2000/night) => ₹2,505.60. Total ₹23,385.60.
	got := computeBookingCharges(2000, 4, 2, 2, "Double", 0.10)

	checks := []struct {
		name string
		got  float64
		want float64
	}{
		{"base", got.Base, 16000},
		{"bed surcharge", got.BedSurcharge, 3200},
		{"child fee", got.ChildFee, 4000},
		{"subtotal", got.Subtotal, 23200},
		{"discount", got.Discount, 2320},
		{"taxable", got.Taxable, 20880},
		{"tax", got.Tax, 2505.6},
		{"total", got.Total, 23385.6},
	}
	for _, c := range checks {
		if !approx(c.got, c.want) {
			t.Errorf("%s = %v, want %v", c.name, c.got, c.want)
		}
	}
}

func TestSingleBedNoSurchargeNegativeChildrenClamped(t *testing.T) {
	got := computeBookingCharges(3000, 2, 1, -5, "Single", 0)
	if got.BedSurcharge != 0 {
		t.Errorf("single bed surcharge = %v, want 0", got.BedSurcharge)
	}
	if got.ChildFee != 0 {
		t.Errorf("negative children not clamped: child fee = %v", got.ChildFee)
	}
	if !approx(got.Total, 6000*1.12) {
		t.Errorf("total = %v, want %v", got.Total, 6000*1.12)
	}
}

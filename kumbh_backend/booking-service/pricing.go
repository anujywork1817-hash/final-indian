package main

// Booking money math, extracted so it can be unit-tested independently
// of the DB and HTTP handler (Phase 2: BUG-03/04 GST slab, BUG-08
// server-authoritative add-on pricing).
//
// The formula MUST stay in lock-step with the Flutter booking form
// (kumbh_tent/lib/features/booking/screens/booking_form_screen.dart):
//   - Double bed adds 20% of the base tent charge
//   - each child aged 5-12 costs ₹500 per night
//   - each child under 5 is free
//   - a coupon discounts the whole subtotal
//   - GST is 12% at a per-unit-night tariff of ₹7,500 or less, 18%
//     above — decided by the NIGHTLY price, never the stay total.

const (
	doubleBedSurchargeRate = 0.20
	childFeePerNight       = 500.0
	// Under-5 stays free — kept as its own bracket (capped at 2,
	// same as 5-12) purely so it's tracked/reported separately, not
	// because it's billed.
	childUnder5FeePerNight = 0.0
	gstThresholdPerNight   = 7500.0
	gstRateLow             = 0.12
	gstRateHigh            = 0.18
	// Matches booking_form_screen.dart's _maxChildrenAbove5/
	// _maxChildrenUnder5 — each bracket capped per booking (not per
	// unit) at 2, regardless of guest count or units. Enforced here
	// too so a tampered client can't claim more children, at either
	// age bracket, than the UI allows.
	maxChildrenAged5to12 = 2
	maxChildrenUnder5    = 2
)

type bookingCharges struct {
	Base           float64
	BedSurcharge   float64
	ChildFee       float64
	ChildUnder5Fee float64
	Subtotal       float64
	Discount       float64
	Taxable        float64
	GSTRate        float64
	Tax            float64
	Total          float64
}

// computeBookingCharges returns the full price breakdown. discountRate
// is the fractional coupon discount already validated by the caller
// (0 when no coupon applies). Both children counts are clamped to 2
// regardless of what the caller passes in.
func computeBookingCharges(pricePerNight, nights, units, childrenAged5to12, childrenUnder5 int, bedType string, discountRate float64) bookingCharges {
	if childrenAged5to12 < 0 {
		childrenAged5to12 = 0
	}
	if childrenAged5to12 > maxChildrenAged5to12 {
		childrenAged5to12 = maxChildrenAged5to12
	}
	if childrenUnder5 < 0 {
		childrenUnder5 = 0
	}
	if childrenUnder5 > maxChildrenUnder5 {
		childrenUnder5 = maxChildrenUnder5
	}

	base := float64(pricePerNight) * float64(nights) * float64(units)

	bed := 0.0
	if bedType == "Double" {
		bed = base * doubleBedSurchargeRate
	}

	child := float64(childrenAged5to12) * childFeePerNight * float64(nights)
	childUnder5 := float64(childrenUnder5) * childUnder5FeePerNight * float64(nights)

	subtotal := base + bed + child + childUnder5
	discount := subtotal * discountRate
	taxable := subtotal - discount

	rate := gstRateLow
	if float64(pricePerNight) > gstThresholdPerNight {
		rate = gstRateHigh
	}
	tax := taxable * rate

	return bookingCharges{
		Base:           base,
		BedSurcharge:   bed,
		ChildFee:       child,
		ChildUnder5Fee: childUnder5,
		Subtotal:       subtotal,
		Discount:       discount,
		Taxable:        taxable,
		GSTRate:        rate,
		Tax:            tax,
		Total:          taxable + tax,
	}
}

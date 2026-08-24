package main

import "testing"

// lockExchangeRateFor's INR/unknown-currency branch never
// touches the database, so it's directly unit-testable. The
// foreign-currency branch (which does a DB lookup) is covered by
// the live integration check run against the running stack —
// see the deployment notes for this phase.

func TestLockExchangeRateFor_INRNeverTouchesDB(t *testing.T) {
	cases := []string{"", "INR", "inr", "  INR  "}
	for _, in := range cases {
		currency, rate, foreign := lockExchangeRateFor(in, 1000)
		if currency != "INR" {
			t.Errorf("lockExchangeRateFor(%q): currency = %q, want INR", in, currency)
		}
		if rate != 1 {
			t.Errorf("lockExchangeRateFor(%q): rate = %v, want 1", in, rate)
		}
		if foreign.Valid {
			t.Errorf("lockExchangeRateFor(%q): foreign_amount should be NULL for INR, got %v", in, foreign.Float64)
		}
	}
}

func TestLockExchangeRateFor_UnknownCurrencyFallsBackToINR(t *testing.T) {
	// A currency this system doesn't recognize must never silently
	// lock in a fabricated rate — it falls back to INR rather than
	// guessing.
	currency, rate, foreign := lockExchangeRateFor("XYZ", 1000)
	if currency != "INR" || rate != 1 || foreign.Valid {
		t.Errorf("unknown currency should fall back to INR/1/NULL, got currency=%q rate=%v foreign.Valid=%v",
			currency, rate, foreign.Valid)
	}
}

package main

import "testing"

func TestReconcileStatus_NoGatewayPaymentIsPending(t *testing.T) {
	got := reconcileStatus(500000, 0, false, 0, 0, false)
	if got != "pending" {
		t.Errorf("got %q, want pending", got)
	}
}

func TestReconcileStatus_GatewayAmountMismatchesBooking(t *testing.T) {
	// The gateway record itself doesn't match what the booking was
	// for — this must be caught even before a bank settlement
	// exists, and must win over every other check.
	got := reconcileStatus(500000, 450000, true, 9000, 441000, true)
	if got != "mismatch" {
		t.Errorf("got %q, want mismatch (leg 1 — booking vs gateway — must fail first)", got)
	}
}

func TestReconcileStatus_NoBankSettlementYetIsPartial(t *testing.T) {
	got := reconcileStatus(500000, 500000, true, 9000, 0, false)
	if got != "partial" {
		t.Errorf("got %q, want partial", got)
	}
}

func TestReconcileStatus_ExactNetSettlementIsMatched(t *testing.T) {
	// 500000 paise gross, 9000 paise fee -> expect 491000 net.
	got := reconcileStatus(500000, 500000, true, 9000, 491000, true)
	if got != "matched" {
		t.Errorf("got %q, want matched", got)
	}
}

func TestReconcileStatus_WithinOneRupeeToleranceIsStillMatched(t *testing.T) {
	got := reconcileStatus(500000, 500000, true, 9000, 491050, true) // ₹0.50 over
	if got != "matched" {
		t.Errorf("got %q, want matched (within ₹1 rounding tolerance)", got)
	}
	got = reconcileStatus(500000, 500000, true, 9000, 490950, true) // ₹0.50 under
	if got != "matched" {
		t.Errorf("got %q, want matched (within ₹1 rounding tolerance)", got)
	}
}

func TestReconcileStatus_BankDepositDoesNotMatchExpectedNetIsMismatch(t *testing.T) {
	// This is the acceptance-criteria case: gateway leg is fine,
	// but what actually landed in the bank doesn't match what
	// should have (short-settled by a few hundred rupees).
	got := reconcileStatus(500000, 500000, true, 9000, 470000, true)
	if got != "mismatch" {
		t.Errorf("got %q, want mismatch", got)
	}
}

func TestReconcileStatus_BankDepositOverExpectedIsAlsoMismatch(t *testing.T) {
	// A bank deposit that's suspiciously HIGHER than expected is
	// just as much a reconciliation problem as one that's short —
	// it must not be waved through as "fine, more money is good".
	got := reconcileStatus(500000, 500000, true, 9000, 550000, true)
	if got != "mismatch" {
		t.Errorf("got %q, want mismatch", got)
	}
}

func TestReconcileStatus_ZeroFeeExactMatch(t *testing.T) {
	got := reconcileStatus(100000, 100000, true, 0, 100000, true)
	if got != "matched" {
		t.Errorf("got %q, want matched", got)
	}
}

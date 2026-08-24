package main

import (
	"time"
)

// ── Tiered cancellation policy ───────────────────────────
//
// Pure calculation: no DB, no network, no clock of its own —
// everything it needs is passed in, so it is exhaustively
// testable (see cancellation_policy_test.go).
//
// This sits ON TOP of the existing RefundPolicy/Quote engine
// in refund_policy.go, which remains the global env-configured
// fallback. This file adds a PER-TENT, NAMED-TIER policy that
// the app's own UI can label with a badge (🟢🟡🟠🔴⚫) — the
// tier a cancellation actually landed on is returned as
// TierApplied, not configured directly: the tent's PolicyType
// only chooses between "always non-refundable" and "run the
// standard tiered ladder using this tent's windows".
//
// All money is in PAISE (integer), same convention as
// refund_policy.go — reuses its applyPercent helper.

// PolicyType is stored per tent.
type PolicyType string

const (
	PolicyFreeCancellation PolicyType = "FREE_CANCELLATION"
	PolicyPartialRefund    PolicyType = "PARTIAL_REFUND"
	PolicyOneNightPenalty  PolicyType = "ONE_NIGHT_PENALTY"
	PolicyNonRefundable    PolicyType = "NON_REFUNDABLE"
)

// TierApplied is the outcome of a single cancellation — always
// one of these five, or one of the "not eligible" markers.
const (
	TierFreeCancellation = "FREE_CANCELLATION"
	TierPartialRefund    = "PARTIAL_REFUND"
	TierOneNightPenalty  = "ONE_NIGHT_PENALTY"
	TierNonRefundable    = "NON_REFUNDABLE"
	TierNoShow           = "NO_SHOW"

	TierAlreadyCancelled = "ALREADY_CANCELLED"
	TierAlreadyRefunded  = "ALREADY_REFUNDED"
	TierNotCancellable   = "NOT_CANCELLABLE" // completed / no_show booking
)

// CancellationPolicyConfig is the per-tent policy, loaded from
// the tents table (see migrations/002_cancellation_policy.sql).
type CancellationPolicyConfig struct {
	PolicyType PolicyType

	// FreeCancellationHours: cancelling at least this many hours
	// before check-in refunds 100%.
	FreeCancellationHours int

	// PartialRefundPenaltyPercent: penalty deducted (of the paid
	// amount) once inside the free-cancellation window but still
	// at or before LateCancellationHours.
	PartialRefundPenaltyPercent float64

	// LateCancellationHours: below this many hours of notice
	// (including cancelling after check-in has already begun),
	// only one night's amount is refunded... rather, one night's
	// amount is WITHHELD and the rest refunded.
	LateCancellationHours int

	// NoShowCutoffHours: hours after the check-in date/time with
	// no check-in recorded before the booking is auto-marked
	// NO_SHOW.
	NoShowCutoffHours int

	// NoShowPenaltyPercent: percent withheld on a no-show.
	NoShowPenaltyPercent float64
}

// BookingForRefund is the minimal snapshot calculateRefund
// needs — deliberately not the full DB row, so the function
// stays pure and easy to construct in tests.
type BookingForRefund struct {
	BookingRef string

	// PaidPaise is what was actually collected (from the
	// payments table / cash-confirmed total), never
	// bookings.total_amount directly — see paidAmountPaise.
	PaidPaise int64

	// NightPaise is the price of a single night for this
	// booking (base price × units), used by the
	// ONE_NIGHT_PENALTY tier.
	NightPaise int64

	// CheckIn is the stay's check-in instant, in a fixed
	// timezone (IST) — see cancellation_policy_test.go and the
	// timezone note in Quote's caller.
	CheckIn time.Time

	// Status is the booking's CURRENT status before this
	// cancellation attempt: "pending", "confirmed", "cancelled",
	// "completed", or "no_show".
	Status string

	// AlreadyRefunded: a refund row already exists for this
	// booking (the unique index on refunds.booking_ref is the
	// real guarantee; this lets the pure function express the
	// same rule defensively, without touching the DB itself).
	AlreadyRefunded bool

	Policy CancellationPolicyConfig
}

// RefundResult is the outcome of applying the tiered policy.
type RefundResult struct {
	RefundAmountPaise  int64
	RefundPercent      float64
	TierApplied        string
	PenaltyAmountPaise int64
	Rule               string
}

// calculateRefund is the core, pure decision function. It is
// SERVER-SIDE ONLY — the Flutter app must never compute this
// itself; it only ever displays what this function (via the
// API) returned.
func calculateRefund(b BookingForRefund, cancellationTimestamp time.Time) RefundResult {
	// ── Guard: not a fresh, cancellable booking ───────────
	switch b.Status {
	case "cancelled":
		return RefundResult{TierApplied: TierAlreadyCancelled, Rule: "booking is already cancelled"}
	case "no_show":
		return RefundResult{TierApplied: TierAlreadyCancelled, Rule: "booking is already marked no-show"}
	case "completed":
		return RefundResult{TierApplied: TierNotCancellable, Rule: "a completed stay cannot be cancelled"}
	}
	if b.AlreadyRefunded {
		return RefundResult{TierApplied: TierAlreadyRefunded, Rule: "a refund already exists for this booking"}
	}
	if b.PaidPaise <= 0 {
		return RefundResult{TierApplied: TierNotCancellable, Rule: "nothing was paid on this booking"}
	}

	// ── NON_REFUNDABLE overrides timing entirely ──────────
	if b.Policy.PolicyType == PolicyNonRefundable {
		return RefundResult{
			RefundAmountPaise:  0,
			RefundPercent:      0,
			TierApplied:        TierNonRefundable,
			PenaltyAmountPaise: b.PaidPaise,
			Rule:               "tent is marked non-refundable",
		}
	}

	// ── Time-based ladder ──────────────────────────────────
	//
	// hoursNotice is how much notice was given before check-in.
	// Cancelling after check-in has already started yields a
	// negative value, which — by design — falls straight
	// through to the ONE_NIGHT_PENALTY branch below: a stay
	// already in progress is never eligible for the free or
	// partial tiers.
	hoursNotice := b.CheckIn.Sub(cancellationTimestamp).Hours()

	switch {
	case hoursNotice >= float64(b.Policy.FreeCancellationHours):
		return RefundResult{
			RefundAmountPaise: b.PaidPaise,
			RefundPercent:     100,
			TierApplied:       TierFreeCancellation,
			Rule:              "cancelled before the free-cancellation deadline",
		}

	case hoursNotice >= float64(b.Policy.LateCancellationHours):
		penalty := applyPercent(b.PaidPaise, b.Policy.PartialRefundPenaltyPercent)
		refund := b.PaidPaise - penalty
		if refund < 0 {
			refund = 0
			penalty = b.PaidPaise
		}
		return RefundResult{
			RefundAmountPaise:  refund,
			RefundPercent:      100 - b.Policy.PartialRefundPenaltyPercent,
			TierApplied:        TierPartialRefund,
			PenaltyAmountPaise: penalty,
			Rule:               "cancelled after the free-cancellation deadline",
		}

	default:
		penalty := b.NightPaise
		if penalty > b.PaidPaise {
			penalty = b.PaidPaise
		}
		if penalty < 0 {
			penalty = 0
		}
		refund := b.PaidPaise - penalty
		percent := 0.0
		if b.PaidPaise > 0 {
			percent = float64(refund) / float64(b.PaidPaise) * 100
		}
		rule := "late cancellation — first night's amount withheld"
		if hoursNotice < 0 {
			rule = "cancelled after check-in had already begun — first night's amount withheld"
		}
		return RefundResult{
			RefundAmountPaise:  refund,
			RefundPercent:      percent,
			TierApplied:        TierOneNightPenalty,
			PenaltyAmountPaise: penalty,
			Rule:               rule,
		}
	}
}

// calculateNoShowRefund is the no-show counterpart: the guest
// never checked in and the cutoff has passed. Unlike
// calculateRefund, this is not triggered by the user — it is
// applied by the no-show sweeper (see noshow.go).
func calculateNoShowRefund(paidPaise int64, policy CancellationPolicyConfig) RefundResult {
	if paidPaise <= 0 {
		return RefundResult{TierApplied: TierNoShow, Rule: "nothing was paid on this booking"}
	}
	penalty := applyPercent(paidPaise, policy.NoShowPenaltyPercent)
	refund := paidPaise - penalty
	if refund < 0 {
		refund = 0
		penalty = paidPaise
	}
	percent := 100 - policy.NoShowPenaltyPercent
	if percent < 0 {
		percent = 0
	}
	return RefundResult{
		RefundAmountPaise:  refund,
		RefundPercent:      percent,
		TierApplied:        TierNoShow,
		PenaltyAmountPaise: penalty,
		Rule:               "guest did not check in by the no-show cutoff",
	}
}

package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ── Refund policy ────────────────────────────────────────
//
// Pure calculation: no DB, no network, no clock of its own.
// Everything it needs is passed in, so it can be tested
// exhaustively (see refund_policy_test.go).
//
// All money is in PAISE (integer). Never float rupees —
// 0.1 + 0.2 problems are not acceptable on a refund.

// RefundTier says: if the cancellation happens at least
// MinHours before check-in, refund Percent of the booking.
type RefundTier struct {
	MinHours int
	Percent  float64
}

// RefundPolicy is assembled once at startup from env vars.
type RefundPolicy struct {
	Enabled bool
	// FeePercent is a processing fee deducted from the
	// gross refund, after the tier percentage is applied.
	FeePercent float64
	// Tiers sorted descending by MinHours. Empty means
	// "always refund 100%".
	Tiers []RefundTier
	// MaxAttempts caps gateway retries per refund.
	MaxAttempts int
	// SettlementDays is the customer-facing promise, e.g. "3-4".
	SettlementDays string
	// RequireApproval holds every refund at 'awaiting_approval'
	// until a human approves it. Nothing is sent to the gateway
	// before then.
	RequireApproval bool
}

// RefundQuote is the outcome of applying a policy.
type RefundQuote struct {
	// RefundPaise is what actually goes back to the customer.
	RefundPaise int64 `json:"refund_amount_paise"`
	// FeePaise is what the business retains as a processing fee.
	FeePaise int64 `json:"fee_paise"`
	// Percent is the tier percentage that applied.
	Percent float64 `json:"policy_percent"`
	// Rule is a human-readable audit string.
	Rule string `json:"policy_rule"`
}

// RefundRupees renders the refund for display, e.g. 1234.50.
func (q RefundQuote) RefundRupees() float64 {
	return float64(q.RefundPaise) / 100.0
}

// applyPercent multiplies a paise amount by a percentage and
// rounds half-up to the nearest paise.
//
// Integer-safe: paise amounts for this app are far below
// 2^53, so float64 represents them exactly; the only
// imprecision possible is in the multiply, which the
// explicit round then resolves deterministically.
func applyPercent(paise int64, percent float64) int64 {
	if paise <= 0 || percent <= 0 {
		return 0
	}
	if percent >= 100 {
		return paise
	}
	// math.Round rounds half away from zero; for positive
	// values that is exactly "round half up".
	return int64(math.Round(float64(paise) * percent / 100.0))
}

// Quote computes what to refund for a booking cancelled at
// `now` whose stay begins at `checkIn`.
//
// Guarantees, upheld by the tests:
//   - never returns more than bookingPaise
//   - never returns a negative amount
//   - RefundPaise + FeePaise <= bookingPaise (matches the
//     ck_refunds_amount_bounds DB constraint)
func (p RefundPolicy) Quote(bookingPaise int64, now, checkIn time.Time) RefundQuote {
	if bookingPaise <= 0 {
		return RefundQuote{Rule: "nothing_paid", Percent: 0}
	}
	if !p.Enabled {
		return RefundQuote{Rule: "refunds_disabled", Percent: 0}
	}

	percent, rule := p.tierFor(now, checkIn)

	gross := applyPercent(bookingPaise, percent)
	fee := applyPercent(gross, p.FeePercent)
	net := gross - fee
	if net < 0 {
		// Defensive: a fee >100% would otherwise invert the sign.
		net = 0
		fee = gross
	}

	// The retained fee for accounting purposes is everything
	// not returned to the customer that we explicitly charged.
	// The tier-withheld portion is not a "fee", it is simply
	// not refundable, so it is not counted in fee_paise.
	return RefundQuote{
		RefundPaise: net,
		FeePaise:    fee,
		Percent:     percent,
		Rule:        rule,
	}
}

// tierFor picks the applicable tier percentage.
func (p RefundPolicy) tierFor(now, checkIn time.Time) (float64, string) {
	if len(p.Tiers) == 0 {
		return 100, "full_refund"
	}

	// Hours of notice given. Cancelling after check-in has
	// already passed yields a negative value, which matches
	// no tier with MinHours >= 0 except a 0-hour floor tier.
	hours := int(math.Floor(checkIn.Sub(now).Hours()))

	for _, t := range p.Tiers {
		if hours >= t.MinHours {
			return t.Percent, fmt.Sprintf("tier_%dh_%gpct", t.MinHours, t.Percent)
		}
	}
	return 0, "no_refund_past_cutoff"
}

// ── Configuration ────────────────────────────────────────

// loadRefundPolicy reads policy from the environment.
//
// Defaults are deliberately the SAFEST possible for the
// customer: refunds enabled, 100% back, zero fee. A
// misconfigured or un-configured deployment therefore
// never silently short-changes anyone. Charging a
// cancellation fee is an explicit, opt-in decision.
func loadRefundPolicy() RefundPolicy {
	p := RefundPolicy{
		Enabled:        envBool("REFUND_ENABLED", true),
		FeePercent:     envFloat("REFUND_FEE_PERCENT", 0),
		Tiers:          parseRefundTiers(os.Getenv("REFUND_TIERS")),
		MaxAttempts:    int(envFloat("REFUND_MAX_ATTEMPTS", 6)),
		SettlementDays: envStr("REFUND_SETTLEMENT_DAYS", "3-4"),
		// Defaults ON: money should not leave the account
		// without someone approving it. Set
		// REFUND_REQUIRE_APPROVAL=false to auto-execute.
		RequireApproval: envBool("REFUND_REQUIRE_APPROVAL", true),
	}
	if p.FeePercent < 0 {
		p.FeePercent = 0
	}
	if p.FeePercent > 100 {
		p.FeePercent = 100
	}
	if p.MaxAttempts < 1 {
		p.MaxAttempts = 1
	}
	return p
}

// parseRefundTiers parses "168:80,72:50,0:0" into tiers,
// meaning: >=168h notice → 80%, >=72h → 50%, else 0%.
//
// Malformed entries are skipped rather than fatal — a typo
// in one tier must not take the booking service down. An
// entirely unparseable value yields no tiers, i.e. 100%,
// which is the safe direction to fail.
func parseRefundTiers(spec string) []RefundTier {
	spec = strings.TrimSpace(spec)
	if spec == "" {
		return nil
	}

	var tiers []RefundTier
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		bits := strings.SplitN(part, ":", 2)
		if len(bits) != 2 {
			fmt.Printf("⚠️  REFUND_TIERS: ignoring malformed entry %q\n", part)
			continue
		}
		// Tolerate a trailing "h" on the hours field.
		hoursStr := strings.TrimSuffix(strings.TrimSpace(bits[0]), "h")
		hours, err := strconv.Atoi(hoursStr)
		if err != nil || hours < 0 {
			fmt.Printf("⚠️  REFUND_TIERS: ignoring bad hours in %q\n", part)
			continue
		}
		pct, err := strconv.ParseFloat(strings.TrimSuffix(strings.TrimSpace(bits[1]), "%"), 64)
		if err != nil || pct < 0 || pct > 100 {
			fmt.Printf("⚠️  REFUND_TIERS: ignoring bad percent in %q\n", part)
			continue
		}
		tiers = append(tiers, RefundTier{MinHours: hours, Percent: pct})
	}

	// Longest notice first, so the first match wins.
	sort.Slice(tiers, func(i, j int) bool {
		return tiers[i].MinHours > tiers[j].MinHours
	})
	return tiers
}

// Describe renders the active policy for logs and the README.
func (p RefundPolicy) Describe() string {
	if !p.Enabled {
		return "refunds DISABLED"
	}
	var b strings.Builder
	if len(p.Tiers) == 0 {
		b.WriteString("100% refund at any notice")
	} else {
		parts := make([]string, 0, len(p.Tiers))
		for _, t := range p.Tiers {
			parts = append(parts, fmt.Sprintf(">=%dh:%g%%", t.MinHours, t.Percent))
		}
		b.WriteString(strings.Join(parts, ", "))
	}
	if p.FeePercent > 0 {
		fmt.Fprintf(&b, " (minus %g%% processing fee)", p.FeePercent)
	}
	if p.RequireApproval {
		b.WriteString("; requires admin approval")
	} else {
		b.WriteString("; auto-approved")
	}
	fmt.Fprintf(&b, "; settles in %s working days", p.SettlementDays)
	return b.String()
}

// ── small env helpers ────────────────────────────────────

func envStr(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func envBool(key string, def bool) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if v == "" {
		return def
	}
	return v == "1" || v == "true" || v == "yes" || v == "on"
}

func envFloat(key string, def float64) float64 {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(strings.TrimSuffix(v, "%"), 64)
	if err != nil {
		fmt.Printf("⚠️  %s=%q is not a number, using default %g\n", key, v, def)
		return def
	}
	return f
}

package main

import (
	"regexp"
	"testing"
)

// BUG-22 regression: OTPs must be a fixed-length decimal string drawn
// from crypto/rand, never from a seedable/predictable source.
func TestSecureNumericCode(t *testing.T) {
	re := regexp.MustCompile(`^[0-9]{6}$`)
	seen := map[string]int{}
	for i := 0; i < 2000; i++ {
		code := secureNumericCode(6)
		if !re.MatchString(code) {
			t.Fatalf("code %q is not 6 decimal digits", code)
		}
		seen[code]++
	}
	// With a uniform 0..999999 draw, 2000 samples colliding heavily
	// would indicate a broken RNG. Allow a little slack.
	if len(seen) < 1990 {
		t.Fatalf("only %d distinct codes in 2000 draws — RNG looks weak", len(seen))
	}
}

func TestSecureNumericCodeLength(t *testing.T) {
	for _, n := range []int{4, 6, 8} {
		if got := len(secureNumericCode(n)); got != n {
			t.Errorf("secureNumericCode(%d) length = %d", n, got)
		}
	}
	// Non-positive length falls back to 6.
	if got := len(secureNumericCode(0)); got != 6 {
		t.Errorf("secureNumericCode(0) length = %d, want 6", got)
	}
}

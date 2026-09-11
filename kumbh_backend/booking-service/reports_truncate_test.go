package main

import "testing"

// BUG: truncateForPDF used to count and slice by byte length, which
// cuts a multi-byte UTF-8 character in half. Guest names/addresses
// in this app are routinely non-ASCII.
func TestTruncateForPDF(t *testing.T) {
	cases := []struct {
		name string
		in   string
		n    int
		want string
	}{
		{"under limit, unchanged", "Ram Kumar", 20, "Ram Kumar"},
		{"exactly at limit, unchanged", "12345", 5, "12345"},
		{"ascii truncation adds ellipsis", "1234567890", 5, "1234…"},
		// "नमस्ते" (Devanagari) is 6 runes but 18 bytes (3 bytes/rune) —
		// a byte-based truncateForPDF(s, 5) would have cut mid-rune.
		{"multi-byte UTF-8 cuts on a rune boundary", "नमस्ते दुनिया", 5, "नमस्…"},
		// Every rune here is 4 bytes — an even more extreme case than
		// Devanagari for a byte-counting truncation to get wrong.
		{"emoji (4-byte runes) cuts on a rune boundary", "🪔🙏🚩🔥🎉", 3, "🪔🙏…"},
		{"n<=0 returns empty", "hello", 0, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := truncateForPDF(tc.in, tc.n)
			if got != tc.want {
				t.Errorf("truncateForPDF(%q, %d) = %q, want %q", tc.in, tc.n, got, tc.want)
			}
			for i, r := range got {
				_ = i
				if r == '�' {
					t.Errorf("truncateForPDF(%q, %d) = %q contains the UTF-8 replacement character — cut mid-rune", tc.in, tc.n, got)
				}
			}
		})
	}
}

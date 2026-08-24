package main

import "testing"

func TestBankAccountFor(t *testing.T) {
	cases := map[string]string{
		"cash":          "Cash",
		"razorpay":      "Bank/Gateway",
		"upi":           "Bank/Gateway",
		"card":          "Bank/Gateway",
		"bank_transfer": "Bank/Gateway",
		"other":         "Bank/Gateway",
		"":              "Bank/Gateway",
	}
	for mode, want := range cases {
		if got := bankAccountFor(mode); got != want {
			t.Errorf("bankAccountFor(%q) = %q, want %q", mode, got, want)
		}
	}
}

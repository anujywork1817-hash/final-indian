package main

import "testing"

// BUG: submitReview 400'd for a 'checked_in' booking with "can only
// review confirmed bookings" - the realistic moment a guest submits
// "How was your stay?" is right after arriving, before the nightly
// auto-complete cron ever flips the booking to 'completed'.
func TestCanReviewBookingStatus(t *testing.T) {
	cases := []struct {
		status string
		want   bool
	}{
		{"confirmed", true},
		{"checked_in", true},
		{"completed", true},
		{"pending", false},
		{"cancelled", false},
		{"no_show", false},
		{"", false},
	}
	for _, tc := range cases {
		t.Run(tc.status, func(t *testing.T) {
			if got := canReviewBookingStatus(tc.status); got != tc.want {
				t.Errorf("canReviewBookingStatus(%q) = %v, want %v", tc.status, got, tc.want)
			}
		})
	}
}

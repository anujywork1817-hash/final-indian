package main

import (
	"strings"

	"github.com/lib/pq"
)

// isUniqueViolation reports whether err is a Postgres unique-key
// violation (SQLSTATE 23505) on an index/constraint whose name
// contains the given substring. Used to tell a genuine duplicate
// (e.g. the same Razorpay payment verified twice — see
// migrations/016_payment_integrity.sql) apart from any other insert
// failure.
func isUniqueViolation(err error, constraint string) bool {
	pqErr, ok := err.(*pq.Error)
	return ok && pqErr.Code == "23505" && (constraint == "" || strings.Contains(string(pqErr.Constraint), constraint))
}

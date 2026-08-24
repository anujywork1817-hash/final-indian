package main

import "fmt"

// ── Ledger posting (online-payment path) ─────────────────
//
// Mirrors booking-service/ledger.go's postLedgerPair — this
// codebase duplicates small per-service helpers rather than
// sharing a package (see sendFCMNotification, email.go,
// invoices.go). payment-service only ever POSTS to the ledger;
// listing/exporting it is booking-service's job.
func postLedgerPair(entryDate, refType, refID, drAccount, crAccount string, amount float64, narration string) {
	if amount <= 0 {
		return
	}
	tx, err := db.Begin()
	if err != nil {
		fmt.Printf("⚠️  ledger: could not post %s %s: %v\n", refType, refID, err)
		return
	}
	defer tx.Rollback()

	if _, err = tx.Exec(`
		INSERT INTO ledger_entries (entry_date, reference_type, reference_id, account, debit, credit, narration)
		VALUES ($1,$2,$3,$4,$5,0,$6)
	`, entryDate, refType, refID, drAccount, amount, narration); err != nil {
		fmt.Printf("⚠️  ledger: could not post %s %s: %v\n", refType, refID, err)
		return
	}
	if _, err = tx.Exec(`
		INSERT INTO ledger_entries (entry_date, reference_type, reference_id, account, debit, credit, narration)
		VALUES ($1,$2,$3,$4,0,$5,$6)
	`, entryDate, refType, refID, crAccount, amount, narration); err != nil {
		fmt.Printf("⚠️  ledger: could not post %s %s: %v\n", refType, refID, err)
		return
	}
	if err = tx.Commit(); err != nil {
		fmt.Printf("⚠️  ledger: could not post %s %s: %v\n", refType, refID, err)
	}
}

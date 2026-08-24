package main

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ── Double-entry Ledger — Phase 6 ────────────────────────
//
// Every booking payment, refund, and expense (see the call sites
// in payment-service/handler.go, revenue.go, refunds.go and
// expenses.go) posts through postLedgerPair — the ONLY way a row
// ever enters this table. There is no HTTP route that lets a
// human create, edit, or delete a ledger row directly; that's
// what makes "system-generated only" true by construction rather
// than by convention.
//
// A correction (refund, expense reversal) is a NEW balanced pair
// with the debit/credit accounts swapped — never an edit to the
// original pair. Because every posting is exactly one debit row
// and one credit row for the same amount, total debits always
// equal total credits across the whole table; that invariant is
// checked directly in ledger_test.go and is also visible via
// GET /admin/ledger's own running totals.

// postLedgerPair posts one balanced (debit, credit) pair. Amounts
// <= 0 are silently skipped — there is nothing to post for a
// zero-value transaction (e.g. a "not_applicable" refund).
func postLedgerPair(entryDate, refType, refID, drAccount, crAccount string, amount float64, narration string) {
	if amount <= 0 {
		return
	}
	tx, err := db.Begin()
	if err != nil {
		logLedgerError(refType, refID, err)
		return
	}
	defer tx.Rollback()

	_, err = tx.Exec(`
		INSERT INTO ledger_entries (entry_date, reference_type, reference_id, account, debit, credit, narration)
		VALUES ($1,$2,$3,$4,$5,0,$6)
	`, entryDate, refType, refID, drAccount, amount, narration)
	if err != nil {
		logLedgerError(refType, refID, err)
		return
	}

	_, err = tx.Exec(`
		INSERT INTO ledger_entries (entry_date, reference_type, reference_id, account, debit, credit, narration)
		VALUES ($1,$2,$3,$4,0,$5,$6)
	`, entryDate, refType, refID, crAccount, amount, narration)
	if err != nil {
		logLedgerError(refType, refID, err)
		return
	}

	if err = tx.Commit(); err != nil {
		logLedgerError(refType, refID, err)
	}
}

func logLedgerError(refType, refID string, err error) {
	fmt.Printf("⚠️  ledger: could not post %s %s: %v\n", refType, refID, err)
}

// bankAccountFor maps a payment_mode to the ledger account name
// money actually moves through. Only 'cash' is the physical till
// — everything else (razorpay, upi, card, bank_transfer, other)
// settles through the bank, so they all map to "Bank/Gateway".
func bankAccountFor(paymentMode string) string {
	if paymentMode == "cash" {
		return "Cash"
	}
	return "Bank/Gateway"
}

// GET /admin/ledger
func adminGetLedger(c *gin.Context) {
	rows, err := db.Query(`
		SELECT entry_date::text, reference_type, reference_id, account, debit, credit,
		       COALESCE(narration,''), created_at::text
		FROM ledger_entries
		ORDER BY entry_date DESC, id DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch ledger"})
		return
	}
	defer rows.Close()

	type entry struct {
		EntryDate     string  `json:"entry_date"`
		ReferenceType string  `json:"reference_type"`
		ReferenceID   string  `json:"reference_id"`
		Account       string  `json:"account"`
		Debit         float64 `json:"debit"`
		Credit        float64 `json:"credit"`
		Narration     string  `json:"narration,omitempty"`
		CreatedAt     string  `json:"created_at"`
	}
	out := []entry{}
	var totalDebit, totalCredit float64
	for rows.Next() {
		var e entry
		if rows.Scan(&e.EntryDate, &e.ReferenceType, &e.ReferenceID, &e.Account,
			&e.Debit, &e.Credit, &e.Narration, &e.CreatedAt) == nil {
			out = append(out, e)
			totalDebit += e.Debit
			totalCredit += e.Credit
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"entries":      out,
		"total":        len(out),
		"total_debit":  totalDebit,
		"total_credit": totalCredit,
		"balanced":     totalDebit == totalCredit,
	})
}

// GET /admin/bank-accounts
//
// "Credits"/"Debits" here use BANKING language (as on a bank
// statement: money IN is a credit, money OUT is a debit) — the
// opposite sense from the ledger's own Dr/Cr for an asset
// account, where money in is a DEBIT. Spelled out explicitly to
// avoid the classic double-entry terminology trap.
func adminGetBankAccounts(c *gin.Context) {
	rows, err := db.Query(`
		SELECT id, account_name, account_type, COALESCE(account_number,''),
		       opening_balance, opening_balance_date::text
		FROM bank_accounts ORDER BY account_type, account_name
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bank accounts"})
		return
	}
	defer rows.Close()

	type account struct {
		ID                 int     `json:"id"`
		AccountName        string  `json:"account_name"`
		AccountType        string  `json:"account_type"`
		AccountNumber      string  `json:"account_number,omitempty"`
		OpeningBalance     float64 `json:"opening_balance"`
		OpeningBalanceDate string  `json:"opening_balance_date"`
		MoneyIn            float64 `json:"money_in"`  // banking "Credits"
		MoneyOut           float64 `json:"money_out"` // banking "Debits"
		ClosingBalance     float64 `json:"closing_balance"`
	}
	out := []account{}
	for rows.Next() {
		var a account
		if rows.Scan(&a.ID, &a.AccountName, &a.AccountType, &a.AccountNumber,
			&a.OpeningBalance, &a.OpeningBalanceDate) != nil {
			continue
		}
		db.QueryRow(`SELECT COALESCE(SUM(debit),0) FROM ledger_entries WHERE account = $1`, a.AccountName).Scan(&a.MoneyIn)
		db.QueryRow(`SELECT COALESCE(SUM(credit),0) FROM ledger_entries WHERE account = $1`, a.AccountName).Scan(&a.MoneyOut)
		a.ClosingBalance = a.OpeningBalance + a.MoneyIn - a.MoneyOut
		out = append(out, a)
	}

	c.JSON(http.StatusOK, gin.H{"accounts": out})
}

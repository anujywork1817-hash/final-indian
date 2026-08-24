package main

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ── Operating Expenses — Phase 3 ─────────────────────────
//
// Tents are self-owned, so this is the money-out side of the
// ledger instead of a vendor-payout module. No edit/update route
// exists anywhere for this table — a mistake is corrected with a
// reversal row (negative amount, reversal_of_id set), the same
// "never edit, only reverse" rule the refund/audit-log system
// already follows.

var expenseCategories = map[string]bool{
	"Tent Maintenance": true, "Transportation": true, "Staff Salary": true,
	"Cleaning": true, "Electricity": true, "Marketing": true, "Rent": true,
	"Insurance": true, "Equipment": true, "Repair": true, "Other": true,
}

var expensePaymentModes = map[string]bool{
	"cash": true, "upi": true, "card": true, "bank_transfer": true, "cheque": true, "other": true,
}

// POST /admin/expenses
func adminCreateExpense(c *gin.Context) {
	var req struct {
		ExpenseDate   string  `json:"expense_date" binding:"required"`
		Category      string  `json:"category" binding:"required"`
		Amount        float64 `json:"amount" binding:"required"`
		Tax           float64 `json:"tax"`
		PaymentMode   string  `json:"payment_mode"`
		AttachmentURL string  `json:"attachment_url"`
		ApprovedBy    string  `json:"approved_by" binding:"required"`
		Note          string  `json:"note"`
		VendorName    string  `json:"vendor_name"`
		PayableStatus string  `json:"payable_status"` // "paid" (default) or "unpaid"
	}
	// ShouldBindJSON already rejects a missing expense_date,
	// category, amount, or approved_by (binding:"required") — the
	// DB's NOT NULL/CHECK constraints are the second, independent
	// enforcement of the same rule.
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "amount must be positive"})
		return
	}
	if !expenseCategories[req.Category] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category"})
		return
	}
	if strings.TrimSpace(req.ApprovedBy) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "approved_by is required"})
		return
	}
	mode := strings.ToLower(strings.TrimSpace(req.PaymentMode))
	if mode == "" {
		mode = "cash"
	}
	if !expensePaymentModes[mode] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment_mode"})
		return
	}
	if _, err := time.Parse("2006-01-02", req.ExpenseDate); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "expense_date must be YYYY-MM-DD"})
		return
	}
	payableStatus := strings.ToLower(strings.TrimSpace(req.PayableStatus))
	if payableStatus == "" {
		payableStatus = "paid"
	}
	if payableStatus != "paid" && payableStatus != "unpaid" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "payable_status must be 'paid' or 'unpaid'"})
		return
	}

	var id int
	err := db.QueryRow(`
		INSERT INTO expenses
			(expense_date, category, amount, tax, payment_mode, attachment_url, approved_by, note, vendor_name, payable_status)
		VALUES ($1,$2,$3,$4,$5,NULLIF($6,''),$7,NULLIF($8,''),NULLIF($9,''),$10)
		RETURNING id
	`, req.ExpenseDate, req.Category, req.Amount, req.Tax, mode,
		req.AttachmentURL, strings.TrimSpace(req.ApprovedBy), req.Note,
		strings.TrimSpace(req.VendorName), payableStatus,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record expense: " + err.Error()})
		return
	}

	// Paid immediately → money already left the bank/till (Dr
	// Expense, Cr Bank). Unpaid → a liability was created instead,
	// nothing has left the bank yet (Dr Expense, Cr Accounts
	// Payable) — settled later via adminMarkExpensePaid.
	crAccount := bankAccountFor(mode)
	if payableStatus == "unpaid" {
		crAccount = "Accounts Payable"
	}
	go postLedgerPair(
		req.ExpenseDate, "expense", strconv.Itoa(id),
		"Operating Expense: "+req.Category, crAccount, req.Amount+req.Tax,
		"Expense approved by "+strings.TrimSpace(req.ApprovedBy),
	)

	c.JSON(http.StatusCreated, gin.H{
		"message": "Expense recorded",
		"id":      id,
	})
}

type expenseRow struct {
	ID            int     `json:"id"`
	ExpenseDate   string  `json:"expense_date"`
	Category      string  `json:"category"`
	Amount        float64 `json:"amount"`
	Tax           float64 `json:"tax"`
	PaymentMode   string  `json:"payment_mode"`
	AttachmentURL string  `json:"attachment_url,omitempty"`
	ApprovedBy    string  `json:"approved_by"`
	Note          string  `json:"note,omitempty"`
	ReversalOfID  *int    `json:"reversal_of_id,omitempty"`
	VendorName    string  `json:"vendor_name,omitempty"`
	PayableStatus string  `json:"payable_status"`
	CreatedAt     string  `json:"created_at"`
}

// GET /admin/expenses?category=&from=&to=
func adminListExpenses(c *gin.Context) {
	query := `
		SELECT id, expense_date, category, amount, tax, payment_mode,
		       COALESCE(attachment_url,''), approved_by, COALESCE(note,''),
		       reversal_of_id, COALESCE(vendor_name,''), payable_status, created_at
		FROM expenses
		WHERE 1=1
	`
	args := []interface{}{}
	if cat := c.Query("category"); cat != "" {
		args = append(args, cat)
		query += " AND category = $" + strconv.Itoa(len(args))
	}
	if from := c.Query("from"); from != "" {
		args = append(args, from)
		query += " AND expense_date >= $" + strconv.Itoa(len(args))
	}
	if to := c.Query("to"); to != "" {
		args = append(args, to)
		query += " AND expense_date <= $" + strconv.Itoa(len(args))
	}
	query += " ORDER BY expense_date DESC, id DESC"

	rows, err := db.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch expenses"})
		return
	}
	defer rows.Close()

	result := []expenseRow{}
	var totalPaise int64
	for rows.Next() {
		var e expenseRow
		var expDate, createdAt time.Time
		if err := rows.Scan(&e.ID, &expDate, &e.Category, &e.Amount, &e.Tax,
			&e.PaymentMode, &e.AttachmentURL, &e.ApprovedBy, &e.Note,
			&e.ReversalOfID, &e.VendorName, &e.PayableStatus, &createdAt); err != nil {
			continue
		}
		e.ExpenseDate = expDate.Format("2006-01-02")
		e.CreatedAt = createdAt.Format("2006-01-02 15:04:05")
		result = append(result, e)
		totalPaise += int64((e.Amount + e.Tax) * 100)
	}

	c.JSON(http.StatusOK, gin.H{
		"expenses":  result,
		"total":     len(result),
		"net_total": float64(totalPaise) / 100.0,
	})
}

// GET /admin/vendor-payables — unpaid expenses only: money the
// business owes a vendor but hasn't sent yet. Distinct from the
// Expenses screen, which shows everything already incurred
// regardless of whether it's been settled.
func adminVendorPayables(c *gin.Context) {
	rows, err := db.Query(`
		SELECT id, expense_date, category, amount, tax, payment_mode,
		       approved_by, COALESCE(note,''), COALESCE(vendor_name,''), created_at
		FROM expenses
		WHERE payable_status = 'unpaid' AND reversal_of_id IS NULL
		ORDER BY expense_date ASC, id ASC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch vendor payables"})
		return
	}
	defer rows.Close()

	type payableRow struct {
		ID          int     `json:"id"`
		ExpenseDate string  `json:"expense_date"`
		Category    string  `json:"category"`
		AmountDue   float64 `json:"amount_due"`
		PaymentMode string  `json:"intended_payment_mode"`
		ApprovedBy  string  `json:"approved_by"`
		Note        string  `json:"note,omitempty"`
		VendorName  string  `json:"vendor_name"`
		DaysOld     int     `json:"days_outstanding"`
		CreatedAt   string  `json:"created_at"`
	}

	out := []payableRow{}
	var totalDuePaise int64
	now := time.Now()
	for rows.Next() {
		var p payableRow
		var expDate, createdAt time.Time
		var amount, tax float64
		if err := rows.Scan(&p.ID, &expDate, &p.Category, &amount, &tax,
			&p.PaymentMode, &p.ApprovedBy, &p.Note, &p.VendorName, &createdAt); err != nil {
			continue
		}
		p.ExpenseDate = expDate.Format("2006-01-02")
		p.CreatedAt = createdAt.Format("2006-01-02 15:04:05")
		p.AmountDue = amount + tax
		p.DaysOld = int(now.Sub(expDate).Hours() / 24)
		if p.VendorName == "" {
			p.VendorName = "Unspecified vendor"
		}
		out = append(out, p)
		totalDuePaise += int64(p.AmountDue * 100)
	}

	c.JSON(http.StatusOK, gin.H{
		"payables":  out,
		"total":     len(out),
		"total_due": float64(totalDuePaise) / 100.0,
	})
}

// POST /admin/expenses/:id/mark-paid
//
// Settles a vendor payable: the liability created at expense-entry
// time (Cr Accounts Payable) is now discharged (Dr Accounts
// Payable, Cr Bank/Cash) — the payable's own reversal-shaped
// ledger correction, distinct from adminReverseExpense which
// corrects a MISTAKEN entry rather than settling a real one.
func adminMarkExpensePaid(c *gin.Context) {
	id := c.Param("id")

	var body struct {
		PaymentMode string `json:"payment_mode" binding:"required"`
		PaidBy      string `json:"paid_by" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "payment_mode and paid_by are required"})
		return
	}
	mode := strings.ToLower(strings.TrimSpace(body.PaymentMode))
	if !expensePaymentModes[mode] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment_mode"})
		return
	}

	var amount, tax float64
	var category, payableStatus string
	err := db.QueryRow(`
		SELECT amount, tax, category, payable_status FROM expenses WHERE id = $1 AND reversal_of_id IS NULL
	`, id).Scan(&amount, &tax, &category, &payableStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "expense not found, or is itself a reversal row"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch expense"})
		return
	}
	if payableStatus != "unpaid" {
		c.JSON(http.StatusConflict, gin.H{"error": "this expense is not an outstanding payable"})
		return
	}

	if _, err := db.Exec(`
		UPDATE expenses SET payable_status = 'paid', paid_at = NOW(), payment_mode = $2 WHERE id = $1
	`, id, mode); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to settle payable: " + err.Error()})
		return
	}

	go postLedgerPair(
		time.Now().Format("2006-01-02"), "vendor_payable_settled", id,
		"Accounts Payable", bankAccountFor(mode), amount+tax,
		"Vendor payable for "+category+" settled by "+strings.TrimSpace(body.PaidBy),
	)

	c.JSON(http.StatusOK, gin.H{"message": "Payable marked as paid", "id": id})
}

// POST /admin/expenses/:id/reverse
//
// Corrects a mistaken expense entry WITHOUT editing or deleting
// it — inserts a negative-amount row referencing the original,
// so the audit trail shows both what was posted and that it was
// reversed, never a silently-changed number.
func adminReverseExpense(c *gin.Context) {
	id := c.Param("id")

	var body struct {
		Reason     string `json:"reason" binding:"required"`
		ApprovedBy string `json:"approved_by" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason and approved_by are required to reverse an expense"})
		return
	}

	var origAmount, origTax float64
	var origCategory, origDate, origPaymentMode string
	var alreadyReversed bool
	err := db.QueryRow(`
		SELECT e.amount, e.tax, e.category, e.expense_date::text, e.payment_mode,
		       EXISTS(SELECT 1 FROM expenses r WHERE r.reversal_of_id = e.id)
		FROM expenses e WHERE e.id = $1 AND e.reversal_of_id IS NULL
	`, id).Scan(&origAmount, &origTax, &origCategory, &origDate, &origPaymentMode, &alreadyReversed)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "expense not found, or is itself a reversal row"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch expense"})
		return
	}
	if alreadyReversed {
		c.JSON(http.StatusConflict, gin.H{"error": "this expense has already been reversed"})
		return
	}

	var reversalID int
	err = db.QueryRow(`
		INSERT INTO expenses
			(expense_date, category, amount, tax, payment_mode, approved_by, note, reversal_of_id)
		VALUES (CURRENT_DATE, $1, $2, $3, 'other', $4, $5, $6)
		RETURNING id
	`, origCategory, -origAmount, -origTax, strings.TrimSpace(body.ApprovedBy),
		"reversal: "+body.Reason, id,
	).Scan(&reversalID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record reversal: " + err.Error()})
		return
	}

	// Auto-reverse ledger entry — accounts swapped from the
	// original expense posting (Cash/Bank Dr, Operating Expense Cr).
	go postLedgerPair(
		time.Now().Format("2006-01-02"), "expense_reversal", strconv.Itoa(reversalID),
		bankAccountFor(origPaymentMode), "Operating Expense: "+origCategory, origAmount+origTax,
		"Reversal of expense #"+id+": "+body.Reason,
	)

	c.JSON(http.StatusCreated, gin.H{
		"message":     "Expense reversed",
		"reversal_id": reversalID,
		"original_id": id,
	})
}

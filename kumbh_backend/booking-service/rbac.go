package main

import (
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// ── Role-based access + admin audit log — Phase 7 QA pass ──
//
// Mirrors auth-service/rbac.go — this codebase duplicates small
// per-service helpers rather than sharing a package (see
// sendFCMNotification, email.go, invoices.go, ledger.go). The
// JWT itself is issued by auth-service's adminLogin and carries
// a "role" claim ('super_admin' or 'staff'); this file only
// verifies and reads it, using the same JWT_SECRET.
//
// Gated here: approving/rejecting a refund, reversing an
// expense, and issuing a credit/debit note — the four actions
// the spec calls out as needing "who can approve" control.
// Recording a NEW expense or payment stays open to any admin;
// only the corrections/approvals that move or reverse money are
// restricted to super_admin.

func adminRoleFromToken(c *gin.Context) (username, role string) {
	tokenStr := c.GetHeader("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") {
		tokenStr = tokenStr[7:]
	}
	if tokenStr == "" {
		return "", ""
	}
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "kumbh2027secret"
	}
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return "", ""
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", ""
	}
	if u, ok := claims["username"].(string); ok {
		username = u
	}
	if r, ok := claims["role"].(string); ok {
		role = r
	}
	return username, role
}

func requireSuperAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		_, role := adminRoleFromToken(c)
		if role != "super_admin" {
			c.JSON(http.StatusForbidden, gin.H{"error": "requires super_admin role"})
			c.Abort()
			return
		}
		c.Next()
	}
}

// adminRoles mirrors api-gateway/security.go's allowlist.
var adminRoles = map[string]bool{"super_admin": true, "admin": true, "staff": true}

// requireAdmin gates every /admin/* route in this service on a
// valid admin JWT of its own, independent of api-gateway's
// adminGuard.
//
// BUG-15: only the four money-moving actions above ever checked
// anything at this layer — every other /admin/* route (coupons,
// bookings, the finance/P&L/GST/ledger/invoice reports, the
// broadcast-notification endpoint) had zero auth at the
// booking-service level. That is safe ONLY as long as nothing can
// reach booking-service except through the gateway; this service is
// reachable on its own port in local/dev (docker-compose.dev.yml)
// and there is nothing architecturally stopping the same being true
// in production if the gateway is ever bypassed, misconfigured, or
// a route added here without also adding it to the gateway. Each
// service must not depend on an upstream hop it cannot verify.
func requireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		_, role := adminRoleFromToken(c)
		if !adminRoles[role] {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "admin authentication required"})
			c.Abort()
			return
		}
		c.Next()
	}
}

func logAdminAction(admin, action, targetType, targetID, details string) {
	db.Exec(`
		INSERT INTO admin_audit_log (admin_username, action, target_type, target_id, details)
		VALUES ($1,$2,$3,$4,$5)
	`, admin, action, targetType, targetID, details)
}

// GET /admin/audit-log — the general admin-mutation trail
// (tent/coupon edits, booking status changes, refund
// approvals, etc). Refund-specific events also have their own
// dedicated trail at GET /admin/finance/bookings/:ref/audit-log;
// this one is the cross-cutting view.
func adminGetAuditLog(c *gin.Context) {
	rows, err := db.Query(`
		SELECT admin_username, action, COALESCE(target_type,''), COALESCE(target_id,''),
		       COALESCE(details,''), created_at::text
		FROM admin_audit_log ORDER BY created_at DESC LIMIT 500
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch audit log"})
		return
	}
	defer rows.Close()

	type entry struct {
		Admin      string `json:"admin_username"`
		Action     string `json:"action"`
		TargetType string `json:"target_type,omitempty"`
		TargetID   string `json:"target_id,omitempty"`
		Details    string `json:"details,omitempty"`
		CreatedAt  string `json:"created_at"`
	}
	out := []entry{}
	for rows.Next() {
		var e entry
		if rows.Scan(&e.Admin, &e.Action, &e.TargetType, &e.TargetID, &e.Details, &e.CreatedAt) == nil {
			out = append(out, e)
		}
	}
	c.JSON(http.StatusOK, gin.H{"entries": out, "total": len(out)})
}

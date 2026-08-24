package main

import (
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// ── Role-based access + admin audit log — Phase 7 QA pass ──
//
// Two admin roles: 'super_admin' (can approve/reject refunds,
// reverse expenses, issue credit/debit notes, create other admin
// accounts) and 'staff' (everything else). Every admin account
// that existed before this migration was promoted to
// super_admin, so nobody is locked out by adding this — only
// accounts created from here on via adminCreateAdmin can be
// 'staff'.
//
// logAdminAction is the one place every audited mutation writes
// through — see its call sites across this file and handler.go.

func logAdminAction(admin, action, targetType, targetID, details string) {
	db.Exec(`
		INSERT INTO admin_audit_log (admin_username, action, target_type, target_id, details)
		VALUES ($1,$2,$3,$4,$5)
	`, admin, action, targetType, targetID, details)
}

// adminRoleFromToken parses the caller's own JWT (the same one
// issued by adminLogin) and returns its role claim, or "" if the
// token is missing/invalid. Used both by requireSuperAdmin and by
// any handler that wants to know who's calling without rejecting
// non-admins outright.
func adminRoleFromToken(c *gin.Context) (username, role string) {
	tokenStr := c.GetHeader("Authorization")
	if len(tokenStr) > 7 && strings.HasPrefix(tokenStr, "Bearer ") {
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

// requireSuperAdmin is attached directly to the specific routes
// that need it (not a blanket group) — see main.go/api-gateway
// for exactly which ones.
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

// GET /auth/admin/list — super_admin only, via requireSuperAdmin
// on the route. Never returns password hashes.
func adminListAdmins(c *gin.Context) {
	rows, err := db.Query(`SELECT username, role, created_at::text FROM admins ORDER BY created_at ASC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch admins"})
		return
	}
	defer rows.Close()

	type adminRow struct {
		Username  string `json:"username"`
		Role      string `json:"role"`
		CreatedAt string `json:"created_at"`
	}
	out := []adminRow{}
	for rows.Next() {
		var a adminRow
		if rows.Scan(&a.Username, &a.Role, &a.CreatedAt) == nil {
			out = append(out, a)
		}
	}
	c.JSON(http.StatusOK, gin.H{"admins": out})
}

// POST /auth/admin/create — super_admin only, via
// requireSuperAdmin on the route.
func adminCreateAdmin(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
		Role     string `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	role := strings.ToLower(strings.TrimSpace(req.Role))
	if role == "" {
		role = "staff"
	}
	if role != "staff" && role != "super_admin" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be 'staff' or 'super_admin'"})
		return
	}

	var count int
	db.QueryRow(`SELECT COUNT(*) FROM admins WHERE username = $1`, req.Username).Scan(&count)
	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "username already taken"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	_, err = db.Exec(`INSERT INTO admins (username, password_hash, role) VALUES ($1,$2,$3)`,
		req.Username, string(hash), role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create admin: " + err.Error()})
		return
	}

	creator, _ := adminRoleFromToken(c)
	logAdminAction(creator, "ADMIN_CREATED", "admin", req.Username, "role="+role)

	c.JSON(http.StatusCreated, gin.H{"message": "Admin account created", "username": req.Username, "role": role})
}

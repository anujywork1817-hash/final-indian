package main

import (
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// ── Admin audit log — Phase 7 QA pass ────────────────────
//
// Mirrors booking-service/rbac.go's logging half (tent-service
// doesn't need requireSuperAdmin — nothing here is gated by
// role, only logged) — same duplication convention as the rest
// of this codebase.

func adminUsernameFromToken(c *gin.Context) string {
	tokenStr := c.GetHeader("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") {
		tokenStr = tokenStr[7:]
	}
	if tokenStr == "" {
		return ""
	}
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "kumbh2027secret"
	}
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return ""
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return ""
	}
	if u, ok := claims["username"].(string); ok {
		return u
	}
	return ""
}

func logAdminAction(admin, action, targetType, targetID, details string) {
	db.Exec(`
		INSERT INTO admin_audit_log (admin_username, action, target_type, target_id, details)
		VALUES ($1,$2,$3,$4,$5)
	`, admin, action, targetType, targetID, details)
}

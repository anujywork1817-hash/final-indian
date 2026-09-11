package main

import (
	"net/http"
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

func adminTokenClaims(c *gin.Context) jwt.MapClaims {
	tokenStr := c.GetHeader("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") {
		tokenStr = tokenStr[7:]
	}
	if tokenStr == "" {
		return nil
	}
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "kumbh2027secret"
	}
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return nil
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil
	}
	return claims
}

func adminUsernameFromToken(c *gin.Context) string {
	claims := adminTokenClaims(c)
	if claims == nil {
		return ""
	}
	if u, ok := claims["username"].(string); ok {
		return u
	}
	return ""
}

// adminRoles mirrors api-gateway/security.go's allowlist.
var adminRoles = map[string]bool{"super_admin": true, "admin": true, "staff": true}

// requireAdmin gates every /admin/* route in this service on a
// valid admin JWT of its own, independent of api-gateway's
// adminGuard.
//
// BUG-15: adminDeleteTent/adminCreateTent/adminUpdateTent used to
// have no auth check at this layer at all — only logged who did it
// (adminUsernameFromToken, best-effort, empty string if no token),
// never rejected an unauthenticated caller. Safe only as long as
// nothing can reach tent-service except through the gateway.
func requireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		claims := adminTokenClaims(c)
		if claims == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "admin authentication required"})
			c.Abort()
			return
		}
		role, _ := claims["role"].(string)
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

package main

import (
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// verifiedPhone extracts the caller's phone number from their own
// Authorization JWT, verified here rather than trusted from the
// X-User-Phone header api-gateway sets. Returns "" if the token is
// missing, malformed, expired, or wrongly signed.
//
// BUG-16: every handler in this service used to do
// `phone := c.GetHeader("X-User-Phone")` and use it directly as the
// caller's identity — fine as long as api-gateway is the only thing
// that can ever reach this service, since it is the one that
// verifies the JWT and sets that header. But nothing at this layer
// enforced that assumption: a request that reached this service
// directly (bypassing the gateway — reachable on its own port in
// local/dev, and nothing architecturally prevents that in production
// too) could set X-User-Phone to any phone number and act as that
// user with zero authentication — read their bookings, cancel them,
// pull their refund history. Verifying the JWT here closes that gap
// independently of the gateway.
func verifiedPhone(c *gin.Context) string {
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
	phone, _ := claims["phone"].(string)
	return phone
}

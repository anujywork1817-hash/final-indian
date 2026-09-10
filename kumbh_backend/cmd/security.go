package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"math/big"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

// This codebase deliberately duplicates small per-service helpers
// rather than sharing a package (see rbac.go, sendFCMNotification,
// email.go). security.go is the same idea for the Phase-1a hardening:
// required-secret checks, a CORS allow-list, and a crypto/rand code
// generator. Keep the copies in sync.

// requireEnv fails the process at startup if any named env var is
// empty. Call it from main() for every secret the service cannot
// safely run without — no more silent "kumbh2027secret" / "test_secret"
// fallbacks.
func requireEnv(keys ...string) {
	var missing []string
	for _, k := range keys {
		if strings.TrimSpace(os.Getenv(k)) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		log.Fatalf("FATAL: required env var(s) not set: %s", strings.Join(missing, ", "))
	}
}

// jwtSecret returns the HMAC signing key. main() has already verified
// JWT_SECRET is set via requireEnv, so this never returns an empty
// key in a correctly-started service.
func jwtSecret() []byte {
	return []byte(os.Getenv("JWT_SECRET"))
}

// corsMiddleware replaces the old `Access-Control-Allow-Origin: *`.
// When CORS_ALLOWED_ORIGINS (comma-separated) is set, only those
// origins are reflected back. When it is unset it falls back to "*"
// with a one-time startup warning, so local dev and not-yet-migrated
// environments keep working — tighten by setting the env var.
func corsMiddleware() gin.HandlerFunc {
	raw := strings.TrimSpace(os.Getenv("CORS_ALLOWED_ORIGINS"))
	var allowed map[string]bool
	if raw != "" {
		allowed = map[string]bool{}
		for _, o := range strings.Split(raw, ",") {
			if o = strings.TrimSpace(o); o != "" {
				allowed[o] = true
			}
		}
	} else {
		log.Println("WARNING: CORS_ALLOWED_ORIGINS not set — allowing all origins (*)")
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if allowed == nil {
			c.Header("Access-Control-Allow-Origin", "*")
		} else if origin != "" && allowed[origin] {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
		}
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type,Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

// secureNumericCode returns a uniformly-random decimal string of the
// given length using crypto/rand — replaces math/rand for OTPs, which
// was seedable/predictable.
func secureNumericCode(digits int) string {
	if digits < 1 {
		digits = 6
	}
	max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(digits)), nil)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		// crypto/rand failing is not recoverable — better to fail
		// the request than to fall back to a weak source.
		panic(fmt.Sprintf("crypto/rand failed: %v", err))
	}
	return fmt.Sprintf("%0*d", digits, n)
}

package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

func TestRequiresAdmin(t *testing.T) {
	cases := map[string]bool{
		"/api/v1/admin/stats":             true,
		"/api/v1/admin/users":             true,
		"/api/v1/admin/refunds/x/approve": true,
		"/api/v1/auth/admin/list":         true,
		"/api/v1/auth/admin/create":       true,
		"/api/v1/auth/admin/login":        false,
		"/api/v1/tents":                   false,
		"/api/v1/bookings":                false,
		"/api/v1/auth/send-otp":           false,
		"/health":                         false,
	}
	for path, want := range cases {
		if got := requiresAdmin(path); got != want {
			t.Errorf("requiresAdmin(%q) = %v, want %v", path, got, want)
		}
	}
}

func adminToken(t *testing.T, role string) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"username": "tester",
		"role":     role,
		"exp":      time.Now().Add(time.Hour).Unix(),
	})
	s, err := tok.SignedString(jwtSecret())
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

// BUG-14 regression: admin routes must reject unauthenticated and
// non-admin callers at the gateway.
func TestAdminGuard(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret-for-gateway")
	gin.SetMode(gin.TestMode)

	r := gin.New()
	r.Use(adminGuard())
	r.GET("/api/v1/admin/stats", func(c *gin.Context) { c.Status(http.StatusOK) })
	r.GET("/api/v1/tents", func(c *gin.Context) { c.Status(http.StatusOK) })

	do := func(path, auth string) int {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		if auth != "" {
			req.Header.Set("Authorization", "Bearer "+auth)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}

	if code := do("/api/v1/admin/stats", ""); code != http.StatusUnauthorized {
		t.Errorf("no token: got %d, want 401", code)
	}
	if code := do("/api/v1/admin/stats", "garbage.token.here"); code != http.StatusUnauthorized {
		t.Errorf("bad token: got %d, want 401", code)
	}
	if code := do("/api/v1/admin/stats", adminToken(t, "tourist")); code != http.StatusForbidden {
		t.Errorf("non-admin role: got %d, want 403", code)
	}
	if code := do("/api/v1/admin/stats", adminToken(t, "super_admin")); code != http.StatusOK {
		t.Errorf("valid super_admin: got %d, want 200", code)
	}
	if code := do("/api/v1/admin/stats", adminToken(t, "staff")); code != http.StatusOK {
		t.Errorf("valid staff: got %d, want 200", code)
	}
	// A non-admin route is untouched by the guard.
	if code := do("/api/v1/tents", ""); code != http.StatusOK {
		t.Errorf("public route: got %d, want 200", code)
	}
}

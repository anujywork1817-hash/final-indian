package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

func sendOTP(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone required"})
		return
	}

	// BUG-21: cap how often one phone number can trigger a send —
	// otherwise this endpoint is an open SMS bomb against any number.
	if rateLimitExceeded("send-otp:"+req.Phone, 5, 15*time.Minute) {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many OTP requests, try again later"})
		return
	}

	otp := fmt.Sprintf("%06d", rand.Intn(1000000))
	expiresAt := time.Now().Add(5 * time.Minute)

	_, err := db.Exec(`
		INSERT INTO otp_store (phone, otp, expires_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (phone) DO UPDATE
		SET otp = $2, expires_at = $3, created_at = NOW()
	`, req.Phone, otp, expiresAt)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store OTP"})
		return
	}

	fmt.Printf("OTP for %s: %s\n", req.Phone, otp)

	c.JSON(http.StatusOK, gin.H{
		"message": "OTP sent successfully",
		"phone":   req.Phone,
		"otp":     otp,
	})
}

func verifyOTP(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
		OTP   string `json:"otp" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// BUG-21: a 6-digit OTP is only 1,000,000 possibilities — cap
	// verify attempts per phone so it can't be brute-forced within
	// its 5-minute validity window.
	if rateLimitExceeded("verify-otp:"+req.Phone, 5, 15*time.Minute) {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many attempts, request a new OTP"})
		return
	}

	var storedOTP string
	var expiresAt time.Time
	err := db.QueryRow(`
		SELECT otp, expires_at FROM otp_store WHERE phone = $1
	`, req.Phone).Scan(&storedOTP, &expiresAt)

	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "OTP not found or expired"})
		return
	}

	if time.Now().After(expiresAt) {
		db.Exec("DELETE FROM otp_store WHERE phone = $1", req.Phone)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "OTP expired"})
		return
	}

	if storedOTP != req.OTP {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid OTP"})
		return
	}

	db.Exec("DELETE FROM otp_store WHERE phone = $1", req.Phone)

	_, err = db.Exec(`
		INSERT INTO users (phone, role)
		VALUES ($1, 'tourist')
		ON CONFLICT (phone) DO NOTHING
	`, req.Phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	var name, email, role string
	db.QueryRow(`
		SELECT COALESCE(name,''), COALESCE(email,''), role
		FROM users WHERE phone = $1
	`, req.Phone).Scan(&name, &email, &role)

	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "kumbh2027secret"
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"phone": req.Phone,
		"role":  role,
		"exp":   time.Now().Add(30 * 24 * time.Hour).Unix(),
	})

	tokenStr, err := token.SignedString([]byte(secret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": tokenStr,
		"user": gin.H{
			"phone": req.Phone,
			"name":  name,
			"email": email,
			"role":  role,
		},
	})
}

// GET /profile
func getProfile(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var name, email, role string
	var bookingCount, reviewCount int

	err := db.QueryRow(`
		SELECT COALESCE(name,''), COALESCE(email,''), role
		FROM users WHERE phone = $1
	`, phone).Scan(&name, &email, &role)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	db.QueryRow(`
		SELECT COUNT(*) FROM bookings WHERE phone = $1
	`, phone).Scan(&bookingCount)

	db.QueryRow(`
		SELECT COUNT(*) FROM reviews WHERE phone = $1
	`, phone).Scan(&reviewCount)

	var kycStatus, idType string
	db.QueryRow(`SELECT COALESCE(kyc_status,'not_submitted'), COALESCE(id_type,'') FROM users WHERE phone = $1`, phone).Scan(&kycStatus, &idType)

	c.JSON(http.StatusOK, gin.H{
		"phone":         phone,
		"name":          name,
		"email":         email,
		"role":          role,
		"booking_count": bookingCount,
		"review_count":  reviewCount,
		"kyc_status":    kycStatus,
		"id_type":       idType,
	})
}

// PUT /profile
func updateProfile(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := db.Exec(`
		UPDATE users SET name = $1, email = $2 WHERE phone = $3
	`, req.Name, req.Email, phone)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update profile"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Profile updated successfully",
		"name":    req.Name,
		"email":   req.Email,
	})
}

// POST /fcm-token
func updateFCMToken(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		FCMToken string `json:"fcm_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := db.Exec(`
		UPDATE users SET fcm_token = $1 WHERE phone = $2
	`, req.FCMToken, phone)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update FCM token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "FCM token updated"})

}

// POST /auth/kyc
func submitKYC(c *gin.Context) {
	phone := c.GetHeader("X-User-Phone")
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		IDType   string `json:"id_type" binding:"required"`
		IDNumber string `json:"id_number" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := db.Exec(`
		UPDATE users SET id_type = $1, id_number = $2, kyc_status = 'pending'
		WHERE phone = $3
	`, req.IDType, req.IDNumber, phone)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to submit KYC"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "KYC submitted successfully", "status": "pending"})
}

// POST /auth/admin/login
func adminLogin(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "username and password required"})
		return
	}

	// BUG-21: cap admin login attempts, both per-username (a
	// targeted password guess against one account) and per-IP (one
	// attacker spraying many usernames) — either exceeding its cap
	// blocks the request.
	if rateLimitExceeded("admin-login:user:"+req.Username, 5, 15*time.Minute) ||
		rateLimitExceeded("admin-login:ip:"+c.ClientIP(), 20, 15*time.Minute) {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many login attempts, try again later"})
		return
	}

	// Find admin in DB
	var passwordHash, role string
	err := db.QueryRow(`SELECT password_hash, role FROM admins WHERE username = $1`, req.Username).Scan(&passwordHash, &role)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	// Compare password with hash
	err = bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	// Generate JWT token
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "kumbh2027secret"
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"username": req.Username,
		"role":     role,
		"exp":      time.Now().Add(24 * time.Hour).Unix(),
	})

	tokenStr, err := token.SignedString([]byte(secret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token error"})
		return
	}

	logAdminAction(req.Username, "ADMIN_LOGIN", "admin", req.Username, "")

	c.JSON(http.StatusOK, gin.H{
		"token":    tokenStr,
		"username": req.Username,
		"role":     role,
	})
}

// POST /auth/admin/change-password
func adminChangePassword(c *gin.Context) {
	var req struct {
		Username    string `json:"username" binding:"required"`
		OldPassword string `json:"old_password" binding:"required"`
		NewPassword string `json:"new_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Find admin
	var passwordHash string
	err := db.QueryRow(`SELECT password_hash FROM admins WHERE username = $1`, req.Username).Scan(&passwordHash)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "admin not found"})
		return
	}

	// Verify old password
	err = bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.OldPassword))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "old password is incorrect"})
		return
	}

	// Hash new password
	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	// Update in DB
	_, err = db.Exec(`UPDATE admins SET password_hash = $1 WHERE username = $2`, string(newHash), req.Username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update password"})
		return
	}

	logAdminAction(req.Username, "ADMIN_PASSWORD_CHANGED", "admin", req.Username, "")

	c.JSON(http.StatusOK, gin.H{"message": "Password changed successfully"})
}

// POST /auth/admin/change-username
func adminChangeUsername(c *gin.Context) {
	var req struct {
		CurrentUsername string `json:"current_username" binding:"required"`
		NewUsername     string `json:"new_username" binding:"required"`
		Password        string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Find admin and verify password
	var passwordHash string
	err := db.QueryRow(`SELECT password_hash FROM admins WHERE username = $1`, req.CurrentUsername).Scan(&passwordHash)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "admin not found"})
		return
	}

	// Verify password
	err = bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "incorrect password"})
		return
	}

	// Check new username not taken
	var count int
	db.QueryRow(`SELECT COUNT(*) FROM admins WHERE username = $1`, req.NewUsername).Scan(&count)
	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "username already taken"})
		return
	}

	// Update username
	_, err = db.Exec(`UPDATE admins SET username = $1 WHERE username = $2`, req.NewUsername, req.CurrentUsername)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update username"})
		return
	}

	logAdminAction(req.NewUsername, "ADMIN_USERNAME_CHANGED", "admin", req.CurrentUsername, "new_username="+req.NewUsername)

	c.JSON(http.StatusOK, gin.H{"message": "Username changed successfully", "new_username": req.NewUsername})
}

// GET /admin/users — all users
func adminGetUsers(c *gin.Context) {
	rows, err := db.Query(`
		SELECT u.phone, COALESCE(u.name,''), COALESCE(u.email,''), u.role,
		       COALESCE(u.kyc_status,'not_submitted'),
		       COUNT(b.id) as booking_count,
		       COALESCE(SUM(b.total_amount),0) as total_spent,
		       u.created_at
		FROM users u
		LEFT JOIN bookings b ON b.phone = u.phone AND b.status != 'cancelled'
		GROUP BY u.phone, u.name, u.email, u.role, u.kyc_status, u.created_at
		ORDER BY u.created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch users"})
		return
	}
	defer rows.Close()

	type User struct {
		Phone        string    `json:"phone"`
		Name         string    `json:"name"`
		Email        string    `json:"email"`
		Role         string    `json:"role"`
		KYCStatus    string    `json:"kyc_status"`
		BookingCount int       `json:"booking_count"`
		TotalSpent   float64   `json:"total_spent"`
		CreatedAt    time.Time `json:"created_at"`
		Status       string    `json:"status"`
	}

	var users []User
	for rows.Next() {
		var u User
		rows.Scan(&u.Phone, &u.Name, &u.Email, &u.Role, &u.KYCStatus, &u.BookingCount, &u.TotalSpent, &u.CreatedAt)
		u.Status = "active"
		if u.Role == "blocked" {
			u.Status = "blocked"
		}
		users = append(users, u)
	}
	if users == nil {
		users = []User{}
	}
	c.JSON(http.StatusOK, gin.H{"users": users, "total": len(users)})
}

// PUT /admin/users/:phone/block — block/unblock user
func adminBlockUser(c *gin.Context) {
	phone := c.Param("phone")
	var req struct {
		Action string `json:"action" binding:"required"` // "block" or "unblock"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	role := "tourist"
	if req.Action == "block" {
		role = "blocked"
	}

	_, err := db.Exec(`UPDATE users SET role = $1 WHERE phone = $2`, role, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user"})
		return
	}

	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "USER_"+strings.ToUpper(req.Action), "user", phone, "")

	c.JSON(http.StatusOK, gin.H{"message": "User " + req.Action + "ed successfully", "phone": phone})
}

func adminGetKYC(c *gin.Context) {
	rows, err := db.Query(`
        SELECT phone, COALESCE(name,''), COALESCE(kyc_status,'not_submitted'), 
        COALESCE(id_type,''), COALESCE(id_number,''), created_at
        FROM users
        WHERE kyc_status IN ('pending','verified','rejected')
        ORDER BY created_at DESC
    `)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch KYC"})
		return
	}
	defer rows.Close()
	var users []map[string]interface{}
	for rows.Next() {
		var phone, name, status, idType, idNumber string
		var createdAt interface{}
		rows.Scan(&phone, &name, &status, &idType, &idNumber, &createdAt)
		users = append(users, map[string]interface{}{
			"phone": phone, "name": name,
			"kyc_status": status, "id_type": idType,
			"id_number": idNumber, "created_at": createdAt,
		})
	}
	if users == nil {
		users = []map[string]interface{}{}
	}
	c.JSON(http.StatusOK, gin.H{"kyc_users": users})
}

func adminVerifyKYC(c *gin.Context) {
	phone := c.Param("phone")
	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Status != "verified" && req.Status != "rejected" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be verified or rejected"})
		return
	}
	_, err := db.Exec(`UPDATE users SET kyc_status = $1 WHERE phone = $2`, req.Status, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update KYC"})
		return
	}
	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "KYC_"+strings.ToUpper(req.Status), "user", phone, "")
	c.JSON(http.StatusOK, gin.H{"message": "KYC status updated", "status": req.Status})
}

package main

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

var otpStore = map[string]string{}

func sendOTP(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone required"})
		return
	}

	otp := secureNumericCode(6)
	otpStore[req.Phone] = otp

	// OTP is delivered only via the SMS/notification channel — never
	// in the HTTP response. Log it only when explicitly opted in.
	if os.Getenv("OTP_DEBUG") == "true" {
		fmt.Printf("[OTP_DEBUG] %s -> %s\n", req.Phone, otp)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "OTP sent successfully",
		"phone":   req.Phone,
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

	stored, exists := otpStore[req.Phone]
	if !exists || stored != req.OTP {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid OTP"})
		return
	}

	delete(otpStore, req.Phone)

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"phone": req.Phone,
		"exp":   time.Now().Add(24 * time.Hour).Unix(),
	})

	tokenStr, err := token.SignedString(jwtSecret())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": tokenStr,
		"user": gin.H{
			"phone": req.Phone,
			"role":  "tourist",
		},
	})
}

func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenStr := c.GetHeader("Authorization")
		if tokenStr == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "no token"})
			c.Abort()
			return
		}

		if len(tokenStr) > 7 && tokenStr[:7] == "Bearer " {
			tokenStr = tokenStr[7:]
		}

		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			return jwtSecret(), nil
		})
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			c.Abort()
			return
		}

		claims := token.Claims.(jwt.MapClaims)
		c.Set("phone", claims["phone"])
		c.Next()
	}
}

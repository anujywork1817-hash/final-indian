package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type Booking struct {
	ID          string    `json:"id"`
	BookingRef  string    `json:"booking_ref"`
	Phone       string    `json:"phone"`
	TentID      string    `json:"tent_id"`
	TentName    string    `json:"tent_name"`
	CheckIn     string    `json:"check_in"`
	CheckOut    string    `json:"check_out"`
	Nights      int       `json:"nights"`
	Guests      int       `json:"guests"`
	TotalAmount float64   `json:"total_amount"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

var bookings []Booking

func createBooking(c *gin.Context) {
	phone := c.GetString("phone")

	var req struct {
		TentID   string `json:"tent_id" binding:"required"`
		CheckIn  string `json:"check_in" binding:"required"`
		CheckOut string `json:"check_out" binding:"required"`
		Guests   int    `json:"guests"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var tent *Tent
	for i := range tents {
		if tents[i].ID == req.TentID {
			tent = &tents[i]
			break
		}
	}
	if tent == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "tent not found"})
		return
	}

	checkIn, _ := time.Parse("2006-01-02", req.CheckIn)
	checkOut, _ := time.Parse("2006-01-02", req.CheckOut)
	nights := int(checkOut.Sub(checkIn).Hours() / 24)
	if nights < 1 {
		nights = 1
	}

	total := float64(tent.Price * nights)
	tax := total * 0.12
	grandTotal := total + tax

	ref := fmt.Sprintf("KTB-2027-%05d", rand.Intn(99999))

	booking := Booking{
		ID:          fmt.Sprintf("%d", rand.Int()),
		BookingRef:  ref,
		Phone:       phone,
		TentID:      req.TentID,
		TentName:    tent.Name,
		CheckIn:     req.CheckIn,
		CheckOut:    req.CheckOut,
		Nights:      nights,
		Guests:      req.Guests,
		TotalAmount: grandTotal,
		Status:      "pending",
		CreatedAt:   time.Now(),
	}
	bookings = append(bookings, booking)

	c.JSON(http.StatusCreated, gin.H{
		"booking":      booking,
		"message":      "Booking created! Complete payment to confirm.",
		"total_amount": grandTotal,
	})
}

func myBookings(c *gin.Context) {
	phone := c.GetString("phone")
	var myB []Booking
	for _, b := range bookings {
		if b.Phone == phone {
			myB = append(myB, b)
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"bookings": myB,
		"total":    len(myB),
	})
}
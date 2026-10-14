package main

import (
	"net/http"
	"github.com/gin-gonic/gin"
)

type Tent struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Class        string   `json:"class"`
	Location     string   `json:"location"`
	Distance     float64  `json:"distance"`
	Rating       float64  `json:"rating"`
	Reviews      int      `json:"reviews"`
	Price        int      `json:"price"`
	BasePrice    int      `json:"base_price"`
	IsSurge      bool     `json:"is_surge"`
	Surge        string   `json:"surge"`
	Amenities    []string `json:"amenities"`
	Capacity     int      `json:"capacity"`
}

var tents = []Tent{
	{
		ID: "1", Name: "Deluxe Sangam View Tent",
		Class: "premium", Location: "Sector 4, Prayagraj",
		Distance: 0.4, Rating: 4.8, Reviews: 124,
		Price: 12500, BasePrice: 5000, IsSurge: true, Surge: "2.5x",
		Amenities: []string{"AC", "Attached Bath", "Meals", "WiFi"},
		Capacity: 2,
	},
	{
		ID: "2", Name: "Premium Kumbh Camp",
		Class: "luxury", Location: "Arail Ghat",
		Distance: 1.2, Rating: 4.6, Reviews: 89,
		Price: 7200, BasePrice: 7200, IsSurge: false, Surge: "",
		Amenities: []string{"AC", "Private Bath", "Geyser", "TV"},
		Capacity: 2,
	},
	{
		ID: "3", Name: "Budget Pilgrim Tent",
		Class: "basic", Location: "Sector 12",
		Distance: 2.8, Rating: 4.1, Reviews: 56,
		Price: 800, BasePrice: 800, IsSurge: false, Surge: "",
		Amenities: []string{"Common Bath", "Meals"},
		Capacity: 4,
	},
	{
		ID: "4", Name: "VIP Maharaja Camp",
		Class: "vip", Location: "Triveni Sangam",
		Distance: 0.1, Rating: 4.9, Reviews: 210,
		Price: 45000, BasePrice: 15000, IsSurge: true, Surge: "3x",
		Amenities: []string{"AC", "Private Bath", "Butler", "Meals", "WiFi"},
		Capacity: 2,
	},
	{
		ID: "5", Name: "Standard Ganga View Camp",
		Class: "standard", Location: "Naini Bridge Area",
		Distance: 1.8, Rating: 4.3, Reviews: 67,
		Price: 2500, BasePrice: 2500, IsSurge: false, Surge: "",
		Amenities: []string{"Fan", "Common Bath", "Meals", "Charging"},
		Capacity: 3,
	},
}

func listTents(c *gin.Context) {
	class := c.Query("class")
	if class == "" || class == "all" {
		c.JSON(http.StatusOK, gin.H{
			"tents": tents,
			"total": len(tents),
		})
		return
	}
	var filtered []Tent
	for _, t := range tents {
		if t.Class == class {
			filtered = append(filtered, t)
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"tents": filtered,
		"total": len(filtered),
	})
}

func getTent(c *gin.Context) {
	id := c.Param("id")
	for _, t := range tents {
		if t.ID == id {
			c.JSON(http.StatusOK, t)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "tent not found"})
}
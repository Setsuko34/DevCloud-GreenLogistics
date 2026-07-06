package simulator

import (
	"encoding/json"
	"os"
	"time"

	"github.com/setsuko34/greenlogistics-gps/publisher"
)

type Waypoint struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type Route struct {
	DriverID       string     `json:"driver_id"`
	ParcelID       string     `json:"parcel_id"`
	TrackingCode   string     `json:"tracking_code"`
	RecipientEmail string     `json:"recipient_email"`
	Destination    Waypoint   `json:"destination"`
	Waypoints      []Waypoint `json:"waypoints"`
}

func LoadRoutes(path string) ([]Route, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var routes []Route
	return routes, json.Unmarshal(data, &routes)
}

// RunDriver simule un livreur qui parcourt ses waypoints en boucle.
func RunDriver(route Route, pub *publisher.Publisher) {
	idx := 0
	notified := false

	for {
		wp := route.Waypoints[idx]

		pub.PublishPosition(route.DriverID, route.ParcelID, wp.Lat, wp.Lng)

		dist := DistanceKm(wp.Lat, wp.Lng, route.Destination.Lat, route.Destination.Lng)
		if dist < 1.0 && !notified {
			pub.PublishNear5Min(route.ParcelID, route.TrackingCode, route.RecipientEmail)
			notified = true
		}

		idx = (idx + 1) % len(route.Waypoints)
		if idx == 0 {
			notified = false // reset pour la prochaine boucle
		}

		time.Sleep(5 * time.Second)
	}
}

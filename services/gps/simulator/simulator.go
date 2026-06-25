package simulator

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/Auguste-p/greenlogistics-gps/publisher"
)

type Waypoint struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type Route struct {
	DriverID       string
	ParcelID       string
	RecipientEmail string
	Destination    Waypoint
	Waypoints      []Waypoint
}

type apiParcel struct {
	ID             string  `json:"id"`
	RecipientEmail string  `json:"recipient_email"`
	DestinationLat float64 `json:"destination_lat"`
	DestinationLng float64 `json:"destination_lng"`
}

// generateWaypoints produit 6 points en ligne droite depuis un départ décalé vers la destination.
func generateWaypoints(dst Waypoint) []Waypoint {
	start := Waypoint{Lat: dst.Lat + 0.04, Lng: dst.Lng - 0.03}
	pts := make([]Waypoint, 6)
	for i := range pts {
		t := float64(i) / float64(len(pts)-1)
		pts[i] = Waypoint{
			Lat: start.Lat + t*(dst.Lat-start.Lat),
			Lng: start.Lng + t*(dst.Lng-start.Lng),
		}
	}
	return pts
}

func FetchRoutes(apiURL string) ([]Route, error) {
	resp, err := http.Get(apiURL + "/parcels")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var parcels []apiParcel
	if err := json.Unmarshal(body, &parcels); err != nil {
		return nil, err
	}
	routes := make([]Route, len(parcels))
	for i, p := range parcels {
		dst := Waypoint{Lat: p.DestinationLat, Lng: p.DestinationLng}
		routes[i] = Route{
			DriverID:       fmt.Sprintf("driver-%d", i+1),
			ParcelID:       p.ID,
			RecipientEmail: p.RecipientEmail,
			Destination:    dst,
			Waypoints:      generateWaypoints(dst),
		}
	}
	return routes, nil
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
			pub.PublishNear5Min(route.ParcelID, route.RecipientEmail)
			notified = true
		}

		idx = (idx + 1) % len(route.Waypoints)
		if idx == 0 {
			notified = false
		}

		time.Sleep(5 * time.Second)
	}
}

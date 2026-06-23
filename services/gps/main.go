package main

import (
	"log"
	"sync"

	"github.com/Auguste-p/greenlogistics-gps/publisher"
	"github.com/Auguste-p/greenlogistics-gps/simulator"
)

func main() {
	routes, err := simulator.LoadRoutes("waypoints.json")
	if err != nil {
		log.Fatalf("Failed to load waypoints: %v", err)
	}

	pub := publisher.New()
	log.Printf("Starting GPS simulator with %d drivers", len(routes))

	var wg sync.WaitGroup
	for _, route := range routes {
		wg.Add(1)
		go func(r simulator.Route) {
			defer wg.Done()
			simulator.RunDriver(r, pub)
		}(route)
	}
	wg.Wait()
}

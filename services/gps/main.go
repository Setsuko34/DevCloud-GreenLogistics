package main

import (
	"log"
	"os"
	"sync"
	"time"

	"github.com/Auguste-p/greenlogistics-gps/publisher"
	"github.com/Auguste-p/greenlogistics-gps/simulator"
)

func main() {
	apiURL := os.Getenv("API_URL")
	if apiURL == "" {
		apiURL = "http://localhost:3000"
	}

	// Attend que l'API soit disponible et qu'il y ait des colis à simuler.
	var routes []simulator.Route
	for {
		var err error
		routes, err = simulator.FetchRoutes(apiURL)
		if err == nil && len(routes) > 0 {
			break
		}
		if err != nil {
			log.Printf("API non disponible, nouvelle tentative dans 5s : %v", err)
		} else {
			log.Printf("Aucun colis trouvé, nouvelle tentative dans 5s...")
		}
		time.Sleep(5 * time.Second)
	}

	pub := publisher.New()
	log.Printf("Démarrage du simulateur GPS avec %d livreur(s)", len(routes))

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

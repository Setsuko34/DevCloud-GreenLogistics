package publisher

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
)

type Publisher struct {
	kafkaWriter *kafka.Writer
	redis       *redis.Client
}

type GPSPosition struct {
	DriverID string  `json:"driver_id"`
	ParcelID string  `json:"parcel_id"`
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	Ts       string  `json:"ts"`
}

type ParcelEvent struct {
	ParcelID       string `json:"parcel_id"`
	TrackingCode   string `json:"tracking_code"`
	Event          string `json:"event"`
	RecipientEmail string `json:"recipient_email"`
}

func New() *Publisher {
	brokers := strings.Split(os.Getenv("REDPANDA_BROKERS"), ",")
	if len(brokers) == 0 || brokers[0] == "" {
		brokers = []string{"localhost:9092"}
	}

	writer := &kafka.Writer{
		Addr:                   kafka.TCP(brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: true,
	}

	addr := os.Getenv("REDIS_URL")
	if addr == "" {
		addr = "localhost:6379"
	}
	rdb := redis.NewClient(&redis.Options{Addr: addr})

	return &Publisher{kafkaWriter: writer, redis: rdb}
}

func (p *Publisher) PublishPosition(driverID, parcelID string, lat, lng float64) {
	pos := GPSPosition{
		DriverID: driverID,
		ParcelID: parcelID,
		Lat:      lat,
		Lng:      lng,
		Ts:       time.Now().UTC().Format(time.RFC3339),
	}

	payload, _ := json.Marshal(pos)

	// Redpanda
	err := p.kafkaWriter.WriteMessages(context.Background(), kafka.Message{
		Topic: "gps.positions",
		Key:   []byte(driverID),
		Value: payload,
	})
	if err != nil {
		log.Printf("kafka write error: %v", err)
	}

	// Redis — position courante
	redisPayload, _ := json.Marshal(map[string]interface{}{
		"lat":       lat,
		"lng":       lng,
		"ts":        pos.Ts,
		"parcel_id": parcelID,
	})
	if err := p.redis.Set(context.Background(),
		fmt.Sprintf("driver:%s:pos", driverID),
		string(redisPayload),
		30*time.Second,
	).Err(); err != nil {
		log.Printf("redis set error: %v", err)
	}
}

func (p *Publisher) PublishNear5Min(parcelID, trackingCode, recipientEmail string) {
	event := ParcelEvent{
		ParcelID:       parcelID,
		TrackingCode:   trackingCode,
		Event:          "near_5min",
		RecipientEmail: recipientEmail,
	}
	payload, _ := json.Marshal(event)
	err := p.kafkaWriter.WriteMessages(context.Background(), kafka.Message{
		Topic: "parcels.events",
		Key:   []byte(parcelID),
		Value: payload,
	})
	if err != nil {
		log.Printf("kafka near_5min error: %v", err)
	}
	log.Printf("Published near_5min for parcel %s", parcelID)
}

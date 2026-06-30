FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o gps-simulator .

FROM scratch
WORKDIR /app
COPY --from=builder /app/gps-simulator .
COPY waypoints.json .
USER 65532:65532
ENTRYPOINT ["/app/gps-simulator"]

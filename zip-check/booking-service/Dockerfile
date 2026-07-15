FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY booking-service/ ./booking-service/
RUN go build -o booking-service ./booking-service/

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/booking-service .
EXPOSE 8083
CMD ["./booking-service"]

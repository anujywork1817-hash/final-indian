FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY tent-service/ ./tent-service/
RUN go build -o tent-service ./tent-service/

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/tent-service .
EXPOSE 8082
CMD ["./tent-service"]

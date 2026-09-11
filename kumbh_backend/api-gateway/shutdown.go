package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// runGracefully starts srv and blocks until either it fails to start
// or the process receives SIGINT/SIGTERM, in which case it drains
// in-flight requests (up to 15s) before returning.
//
// BUG (graceful shutdown): every service used to call
// `log.Fatal(srv.ListenAndServe())` directly. log.Fatal calls
// os.Exit(1) — the deploy platform's SIGTERM during a rolling
// restart or scale-in (EB/ECS/`docker stop`) killed the process
// immediately, cutting off whatever request was mid-flight (a
// createBooking or verifyPayment call included) and skipping every
// deferred cleanup in main(), db.Close() included.
func runGracefully(srv *http.Server, label string) {
	errCh := make(chan error, 1)
	go func() {
		errCh <- srv.ListenAndServe()
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		if err != nil && err != http.ErrServerClosed {
			fmt.Printf("❌ %s: listen failed: %v\n", label, err)
			os.Exit(1)
		}
	case sig := <-sigCh:
		fmt.Printf("🛑 %s: received %s, draining in-flight requests...\n", label, sig)
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			fmt.Printf("⚠️  %s: graceful shutdown timed out: %v\n", label, err)
		} else {
			fmt.Printf("✅ %s: shut down cleanly\n", label)
		}
	}
}

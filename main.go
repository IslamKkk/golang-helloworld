package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

func newHandler(version string) http.Handler {
	startedAt := time.Now()
	var requests atomic.Uint64
	mux := http.NewServeMux()

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = fmt.Fprintln(w, "Hello from the diploma service")
	})

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_, _ = fmt.Fprintln(w, "{\"status\":\"ok\"}")
	})

	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		_, _ = fmt.Fprintf(w, "# HELP http_requests_total Total HTTP requests handled by the service.\n# TYPE http_requests_total counter\nhttp_requests_total %d\n", requests.Load())
		_, _ = fmt.Fprintf(w, "# HELP process_uptime_seconds Time the service has been running.\n# TYPE process_uptime_seconds gauge\nprocess_uptime_seconds %.3f\n", time.Since(startedAt).Seconds())
		_, _ = fmt.Fprintf(w, "# HELP app_info Service build information.\n# TYPE app_info gauge\napp_info{version=\"%s\"} 1\n", escapeLabelValue(version))
	})

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		mux.ServeHTTP(w, r)
	})
}

func escapeLabelValue(value string) string {
	return strings.NewReplacer("\\", "\\\\", "\n", "\\n", "\"", "\\\"").Replace(value)
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 1 || portNumber > 65535 {
		logger.Error("invalid PORT value", "value", port)
		os.Exit(1)
	}

	version := strings.TrimSpace(os.Getenv("APP_VERSION"))
	if version == "" {
		version = "dev"
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           newHandler(version),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	shutdown, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	serveResult := make(chan error, 1)

	go func() {
		logger.Info("service started", "address", server.Addr, "version", version)
		serveResult <- server.ListenAndServe()
	}()

	select {
	case err := <-serveResult:
		if !errors.Is(err, http.ErrServerClosed) {
			logger.Error("service stopped", "error", err)
			os.Exit(1)
		}
	case <-shutdown.Done():
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(ctx); err != nil {
			logger.Error("graceful shutdown failed", "error", err)
			_ = server.Close()
			os.Exit(1)
		}
		if err := <-serveResult; err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("service stopped", "error", err)
			os.Exit(1)
		}
	}
}

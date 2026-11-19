// Package app wires the server together: connections, routes, and the HTTP
// server.
package app

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"connectrpc.com/grpchealth"

	"github.com/kronoer/kronoer/server/internal/config"
	"github.com/kronoer/kronoer/server/internal/gen/proto/kronoer/server/v1/serverv1connect"
	"github.com/kronoer/kronoer/server/internal/platform/objectstore"
	"github.com/kronoer/kronoer/server/internal/platform/postgres"
	"github.com/kronoer/kronoer/server/internal/serverinfo"
)

// Serve connects to PostgreSQL and the object storage, then serves until ctx
// is done, and shuts down gracefully.
func Serve(ctx context.Context, cfg config.Config, logger *slog.Logger, version string) error {
	if err := cfg.S3.Validate(); err != nil {
		return err
	}
	pool, err := postgres.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	store := objectstore.New(cfg.S3)
	if err := store.Check(ctx); err != nil {
		return err
	}

	// HTTP/1.1 for Connect and gRPC-Web, unencrypted HTTP/2 for gRPC. TLS is
	// ended by the proxy in front of the server.
	protocols := new(http.Protocols)
	protocols.SetHTTP1(true)
	protocols.SetUnencryptedHTTP2(true)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           routes(version),
		Protocols:         protocols,
		ReadHeaderTimeout: 10 * time.Second,
	}

	errc := make(chan error, 1)
	go func() {
		logger.Info("listening", "addr", cfg.Addr, "version", version)
		errc <- srv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}

	logger.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return err
	}
	if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// Migrate applies pending database migrations.
func Migrate(ctx context.Context, cfg config.Config, logger *slog.Logger) error {
	pool, err := postgres.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	return postgres.Migrate(ctx, pool, logger)
}

func routes(version string) http.Handler {
	mux := http.NewServeMux()
	mux.Handle(serverv1connect.NewServerServiceHandler(serverinfo.New(version)))
	mux.Handle(grpchealth.NewHandler(grpchealth.NewStaticChecker(serverv1connect.ServerServiceName)))
	return mux
}

// Command kronoerserver runs the Kronoer server.
//
// Usage:
//
//	kronoerserver serve     start the server
//	kronoerserver migrate   apply pending database migrations, then exit
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/kronoer/kronoer/server/internal/app"
	"github.com/kronoer/kronoer/server/internal/config"
)

// version is set at build time with -ldflags "-X main.version=...".
var version = "dev"

var errUsage = errors.New("usage: kronoerserver serve|migrate")

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "kronoerserver:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) != 1 {
		return errUsage
	}

	cfg, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	logger := newLogger(cfg.LogFormat)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	switch args[0] {
	case "serve":
		return app.Serve(ctx, cfg, logger, version)
	case "migrate":
		return app.Migrate(ctx, cfg, logger)
	default:
		return errUsage
	}
}

func newLogger(format string) *slog.Logger {
	if format == "text" {
		return slog.New(slog.NewTextHandler(os.Stderr, nil))
	}
	return slog.New(slog.NewJSONHandler(os.Stderr, nil))
}

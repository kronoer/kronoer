package postgres

import (
	"context"
	"io"
	"log/slog"
	"os"
	"testing"
)

// TestMigrate needs a database: `just up` locally, a service container in CI.
func TestMigrate(t *testing.T) {
	url := os.Getenv("KRONOER_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("KRONOER_TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	pool, err := Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	// Twice: the second run must find nothing to do.
	for range 2 {
		if err := Migrate(ctx, pool, logger); err != nil {
			t.Fatal(err)
		}
	}
}

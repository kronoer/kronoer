// Package postgres opens the PostgreSQL pool and applies migrations.
package postgres

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"

	"github.com/kronoer/kronoer/server/db"
)

// Open connects to url and checks the connection.
func Open(ctx context.Context, url string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("postgres: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("postgres: %w", err)
	}
	return pool, nil
}

// Migrate applies every pending migration in db/migrations. A session lock
// keeps two runs from migrating at the same time.
func Migrate(ctx context.Context, pool *pgxpool.Pool, logger *slog.Logger) error {
	sqlDB := stdlib.OpenDBFromPool(pool)
	defer sqlDB.Close()

	locker, err := lock.NewPostgresSessionLocker()
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	provider, err := goose.NewProvider(goose.DialectPostgres, sqlDB, db.Migrations(),
		goose.WithSessionLocker(locker))
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}

	results, err := provider.Up(ctx)
	for _, r := range results {
		logger.Info("migration applied", "file", r.Source.Path, "duration", r.Duration)
	}
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	if len(results) == 0 {
		logger.Info("no pending migrations")
	}
	return nil
}

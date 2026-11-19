// Package config reads the server's settings from KRONOER_ environment
// variables. There is no config file.
package config

import (
	"errors"
	"fmt"
)

// Config holds every setting of the server.
type Config struct {
	// Addr is the address to listen on. KRONOER_ADDR, default ":8080".
	Addr string
	// LogFormat is "json" or "text". KRONOER_LOG_FORMAT, default "json".
	LogFormat string
	// DatabaseURL is the PostgreSQL connection string. KRONOER_DATABASE_URL,
	// required.
	DatabaseURL string
	// S3 is the object storage. Only serve needs it.
	S3 S3
}

// S3 holds the settings of the S3-compatible object storage.
type S3 struct {
	// Endpoint is the URL of an S3-compatible service, for example
	// "http://localhost:9000". Empty means Amazon S3. KRONOER_S3_ENDPOINT.
	Endpoint string
	// Region is KRONOER_S3_REGION, default "us-east-1".
	Region string
	// Bucket holds every blob. KRONOER_S3_BUCKET.
	Bucket string
	// AccessKey is KRONOER_S3_ACCESS_KEY.
	AccessKey string
	// SecretKey is KRONOER_S3_SECRET_KEY.
	SecretKey string
}

// Load reads the settings through getenv, which is os.Getenv outside tests.
func Load(getenv func(string) string) (Config, error) {
	c := Config{
		Addr:        getenv("KRONOER_ADDR"),
		LogFormat:   getenv("KRONOER_LOG_FORMAT"),
		DatabaseURL: getenv("KRONOER_DATABASE_URL"),
		S3: S3{
			Endpoint:  getenv("KRONOER_S3_ENDPOINT"),
			Region:    getenv("KRONOER_S3_REGION"),
			Bucket:    getenv("KRONOER_S3_BUCKET"),
			AccessKey: getenv("KRONOER_S3_ACCESS_KEY"),
			SecretKey: getenv("KRONOER_S3_SECRET_KEY"),
		},
	}

	if c.Addr == "" {
		c.Addr = ":8080"
	}
	switch c.LogFormat {
	case "":
		c.LogFormat = "json"
	case "json", "text":
	default:
		return Config{}, fmt.Errorf("config: KRONOER_LOG_FORMAT must be json or text, not %q", c.LogFormat)
	}
	if c.DatabaseURL == "" {
		return Config{}, errors.New("config: KRONOER_DATABASE_URL is required")
	}
	if c.S3.Region == "" {
		c.S3.Region = "us-east-1"
	}
	return c, nil
}

// Validate reports the first missing S3 setting.
func (s S3) Validate() error {
	for _, v := range []struct{ name, value string }{
		{"KRONOER_S3_BUCKET", s.Bucket},
		{"KRONOER_S3_ACCESS_KEY", s.AccessKey},
		{"KRONOER_S3_SECRET_KEY", s.SecretKey},
	} {
		if v.value == "" {
			return fmt.Errorf("config: %s is required", v.name)
		}
	}
	return nil
}

// Package objectstore talks to the S3-compatible storage that holds blobs.
package objectstore

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	"github.com/kronoer/kronoer/server/internal/config"
)

// Store is one bucket.
type Store struct {
	client *s3.Client
	bucket string
}

// New makes a client. It does not connect yet; call Check for that.
func New(cfg config.S3) *Store {
	client := s3.New(s3.Options{
		Region:      cfg.Region,
		Credentials: credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
		// Many S3-compatible services reject the checksums the SDK adds by
		// default; send them only where the S3 API requires them.
		RequestChecksumCalculation: aws.RequestChecksumCalculationWhenRequired,
		ResponseChecksumValidation: aws.ResponseChecksumValidationWhenRequired,
	}, func(o *s3.Options) {
		if cfg.Endpoint != "" {
			o.BaseEndpoint = aws.String(cfg.Endpoint)
			o.UsePathStyle = true
		}
	})
	return &Store{client: client, bucket: cfg.Bucket}
}

// Check reports whether the bucket exists and can be reached.
func (s *Store) Check(ctx context.Context) error {
	if _, err := s.client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(s.bucket)}); err != nil {
		return fmt.Errorf("objectstore: bucket %q: %w", s.bucket, err)
	}
	return nil
}

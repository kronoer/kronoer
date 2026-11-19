// Package serverinfo answers ServerService, which tells a client what this
// server is before it signs in.
package serverinfo

import (
	"context"

	"connectrpc.com/connect"

	serverv1 "github.com/kronoer/kronoer/server/internal/gen/proto/kronoer/server/v1"
)

// entryFormatVersions are the Entry format versions this server accepts,
// from spec/entry-format.md.
var entryFormatVersions = []uint32{1}

// Handler implements serverv1connect.ServerServiceHandler.
type Handler struct {
	version string
}

// New returns a Handler that reports version as the server build.
func New(version string) *Handler {
	return &Handler{version: version}
}

// GetInfo returns the server build and the supported Entry format versions.
func (h *Handler) GetInfo(
	_ context.Context,
	_ *connect.Request[serverv1.GetInfoRequest],
) (*connect.Response[serverv1.GetInfoResponse], error) {
	return connect.NewResponse(&serverv1.GetInfoResponse{
		Version:             h.version,
		EntryFormatVersions: entryFormatVersions,
	}), nil
}

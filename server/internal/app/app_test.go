package app

import (
	"context"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"connectrpc.com/connect"

	serverv1 "github.com/kronoer/kronoer/server/internal/gen/proto/kronoer/server/v1"
	"github.com/kronoer/kronoer/server/internal/gen/proto/kronoer/server/v1/serverv1connect"
)

func TestGetInfo(t *testing.T) {
	srv := httptest.NewServer(routes("test"))
	defer srv.Close()

	client := serverv1connect.NewServerServiceClient(http.DefaultClient, srv.URL)
	res, err := client.GetInfo(context.Background(), connect.NewRequest(&serverv1.GetInfoRequest{}))
	if err != nil {
		t.Fatal(err)
	}
	if got := res.Msg.GetVersion(); got != "test" {
		t.Errorf("version = %q, want %q", got, "test")
	}
	if got := res.Msg.GetEntryFormatVersions(); !slices.Equal(got, []uint32{1}) {
		t.Errorf("entry format versions = %v, want [1]", got)
	}
}

func TestHealth(t *testing.T) {
	srv := httptest.NewServer(routes("test"))
	defer srv.Close()

	// The gRPC health service answers Connect's JSON over plain HTTP too.
	res, err := http.Post(srv.URL+"/grpc.health.v1.Health/Check", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", res.StatusCode)
	}
}

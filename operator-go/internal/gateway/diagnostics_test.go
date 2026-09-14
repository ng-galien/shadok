package gateway

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"shadok.org/operator/internal/syncer"
	"strings"
	"testing"
)

func TestReceiverRejectionReachesClient(t *testing.T) {
	receiver := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unknown mount classes", http.StatusBadRequest)
	}))
	defer receiver.Close()
	gateway := httptest.NewServer(LogRequests(&Handler{Resolver: resolverFunc(func(context.Context, string, string) ([]Target, error) {
		return []Target{{Name: "orders-live-pod", UID: "one", URL: receiver.URL}}, nil
	})}))
	defer gateway.Close()
	src := t.TempDir()
	os.WriteFile(filepath.Join(src, "file"), []byte("test"), 0600)
	snapshot, err := syncer.Capture([]syncer.Root{{Mount: "classes", Path: src}}, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(snapshot.Dir)
	_, err = syncer.Send(context.Background(), gateway.Client(), gateway.URL+"/team/orders", "", snapshot)
	for _, part := range []string{"plan", "orders-live-pod", "400", "unknown mount classes"} {
		if err == nil || !strings.Contains(err.Error(), part) {
			t.Fatalf("lost diagnostic %s: %v", part, err)
		}
	}
}

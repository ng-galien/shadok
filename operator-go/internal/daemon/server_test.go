package daemon

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"shadok.org/operator/internal/syncer"
	"testing"
	"time"
)

func TestUnwatchDoesNotWaitForStalledNetwork(t *testing.T) {
	entered := make(chan struct{}, 1)
	release := make(chan struct{})
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		entered <- struct{}{}
		select {
		case <-release:
		case <-r.Context().Done():
		}
	}))
	defer remote.Close()
	defer close(release)
	root := t.TempDir()
	os.WriteFile(root+"/file", []byte("data"), 0600)
	state := t.TempDir()
	snapshot, err := syncer.Capture([]syncer.Root{{Mount: "app", Path: root}}, state)
	if err != nil {
		t.Fatal(err)
	}
	j := &Job{ID: "test", Snapshot: snapshot, Destination: Destination{URL: remote.URL}}
	s := &Server{Dir: state}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() { s.loop(ctx, j); close(done) }()
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("delivery did not start")
	}
	if !j.mu.TryLock() {
		t.Fatal("network delivery blocks status/unwatch")
	}
	replaceSnapshot(j, nil)
	j.mu.Unlock()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("unwatch did not cancel delivery")
	}
	if _, err := os.Stat(snapshot.Dir); !os.IsNotExist(err) {
		t.Fatal("stopped snapshot was not reclaimed", err)
	}
}

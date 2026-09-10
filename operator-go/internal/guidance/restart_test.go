package guidance

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"shadok.org/operator/internal/daemon"
)

// Exercise the persistence contract documented in the binary against the actual
// server: stop retains a saved group; unwatch removes it across the next start.
func TestDocumentedDaemonRestartContract(t *testing.T) {
	dir, err := os.MkdirTemp("", "sd-guide-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(dir)
	// macOS Unix sockets have a short pathname limit.
	if len(filepath.Join(dir, "daemon.sock")) > 100 {
		t.Skip("temporary path exceeds Unix socket length limit")
	}
	client := &http.Client{Timeout: time.Second, Transport: &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", filepath.Join(dir, "daemon.sock"))
	}}}
	defer client.CloseIdleConnections()
	start := func() func() {
		ctx, cancel := context.WithCancel(context.Background())
		done := make(chan struct{})
		go func() { defer close(done); _ = daemon.Serve(ctx, dir) }()
		stop := func() {
			cancel()
			select {
			case <-done:
			case <-time.After(3 * time.Second):
				t.Error("daemon did not stop")
			}
			client.CloseIdleConnections()
		}
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			r, e := client.Get("http://daemon/health")
			if e == nil {
				r.Body.Close()
				return stop
			}
			time.Sleep(10 * time.Millisecond)
		}
		stop()
		t.Fatal("daemon not ready")
		return nil
	}
	request := func(method string, body []byte) []byte {
		req, _ := http.NewRequest(method, "http://daemon/jobs", bytes.NewReader(body))
		res, e := client.Do(req)
		if e != nil {
			t.Fatal(e)
		}
		defer res.Body.Close()
		b, _ := io.ReadAll(res.Body)
		if res.StatusCode != 200 {
			t.Fatalf("%s: %d %s", method, res.StatusCode, b)
		}
		return b
	}
	job := daemon.Job{Config: "/project/shadok.yaml", Group: "service"}
	job.ID = daemon.ID(job.Config, job.Group, job.Destination)
	payload, _ := json.Marshal(&job)
	stop := start()
	request("POST", payload)
	stop()
	stop = start()
	var jobs []daemon.Job
	if err = json.Unmarshal(request("GET", nil), &jobs); err != nil {
		t.Fatal(err)
	}
	if len(jobs) != 1 || jobs[0].ID != job.ID {
		t.Fatalf("saved group did not resume: %+v", jobs)
	}
	request("DELETE", payload)
	stop()
	stop = start()
	defer stop()
	if err = json.Unmarshal(request("GET", nil), &jobs); err != nil {
		t.Fatal(err)
	}
	if len(jobs) != 0 {
		t.Fatal("unwatched group resumed")
	}
}

package daemon

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSessionOutputsNeedNoLocalConfiguration(t *testing.T) {
	local := "target/classes"
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/sessions/team/live" || r.Method != "GET" {
			t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
		}
		fmt.Fprintf(w, `{"roots":[{"mount":"classes","path":%q}]}`, local)
	}))
	defer s.Close()
	project := t.TempDir()
	d := Destination{URL: s.URL, Namespace: "team", Session: "live"}
	g, err := LoadSession(context.Background(), d, project)
	if err != nil {
		t.Fatal(err)
	}
	if len(g.Roots) != 1 || g.Roots[0].Path != filepath.Join(project, "target/classes") {
		t.Fatalf("wrong roots: %+v", g.Roots)
	}
	os.MkdirAll(g.Roots[0].Path, 0700)
	if err := ValidateSessionRoots(project, g.Roots); err != nil {
		t.Fatal(err)
	}
	local = "../private"
	if _, err := LoadSession(context.Background(), d, project); err == nil {
		t.Fatal("outside project accepted")
	}
	local = "outside"
	os.Symlink(t.TempDir(), filepath.Join(project, local))
	g, err = LoadSession(context.Background(), d, project)
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidateSessionRoots(project, g.Roots); err == nil {
		t.Fatal("symlink escape accepted")
	}
}

func TestSessionLookupPreservesGatewayError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "session is not live", http.StatusConflict)
	}))
	defer server.Close()
	_, err := LoadSession(context.Background(), Destination{URL: server.URL, Namespace: "team", Session: "orders"}, t.TempDir())
	if err == nil || !strings.Contains(err.Error(), "team/orders: HTTP 409: session is not live") {
		t.Fatalf("lost gateway error: %v", err)
	}
}

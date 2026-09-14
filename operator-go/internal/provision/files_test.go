package provision

import (
	"context"
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDownloadChecksBeforePublishing(t *testing.T) {
	s := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "tool") }))
	defer s.Close()
	f := File{Directory: t.TempDir(), Path: "devtools.jar", URL: s.URL, SHA256: fmt.Sprintf("%x", sha256.Sum256([]byte("tool")))}
	if err := download(context.Background(), s.Client(), f); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(f.Directory, f.Path)
	info, _ := os.Stat(dest)
	if info.Mode().Perm() != 0444 {
		t.Fatal("tool is not read-only")
	}
	f.SHA256 = strings.Repeat("0", 64)
	if err := download(context.Background(), s.Client(), f); err == nil {
		t.Fatal("wrong checksum accepted")
	}
	got, _ := os.ReadFile(dest)
	if string(got) != "tool" {
		t.Fatal("failed download replaced existing tool")
	}
	entries, _ := os.ReadDir(f.Directory)
	if len(entries) != 1 {
		t.Fatal("temporary download leaked")
	}
	f.Path = "../escape"
	if err := Validate(f); err == nil {
		t.Fatal("path escape accepted")
	}
}

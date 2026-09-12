package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"shadok.org/operator/internal/buildinfo"
)

func TestReleaseDownloadRejectsCorruption(t *testing.T) {
	var archive bytes.Buffer
	gz := gzip.NewWriter(&archive)
	tr := tar.NewWriter(gz)
	payload := []byte("test executable")
	if err := tr.WriteHeader(&tar.Header{Name: "shadok", Mode: 0755, Size: int64(len(payload)), Typeflag: tar.TypeReg}); err != nil {
		t.Fatal(err)
	}
	tr.Write(payload)
	tr.Close()
	gz.Close()
	digest := fmt.Sprintf("%x", sha256.Sum256(archive.Bytes()))
	corrupt := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "SHA256SUMS") {
			fmt.Fprintf(w, "%s  shadok_1.2.3_%s_%s.tar.gz\n", digest, runtime.GOOS, runtime.GOARCH)
			return
		}
		if corrupt {
			w.Write([]byte("corrupt"))
			return
		}
		w.Write(archive.Bytes())
	}))
	defer server.Close()
	got, err := releaseBinary(context.Background(), server.URL, "1.2.3")
	if err != nil || !bytes.Equal(got, payload) {
		t.Fatal(err, string(got))
	}
	corrupt = true
	if _, err := releaseBinary(context.Background(), server.URL, "1.2.3"); err == nil || !strings.Contains(err.Error(), "SHA256 mismatch") {
		t.Fatal("corruption accepted", err)
	}
}

func TestClusterUpgradePreservesValuesAndDryRunDoesNotApply(t *testing.T) {
	old := buildinfo.Version
	buildinfo.Version = "1.2.3"
	t.Cleanup(func() { buildinfo.Version = old })
	dir := t.TempDir()
	log := filepath.Join(dir, "commands")
	t.Setenv("UPGRADE_LOG", log)
	helm := `#!/bin/sh
printf '%s\n' "helm $*" >> "$UPGRADE_LOG"
case "$*" in
 *"get values"*) printf '%s\n' '{"operator":{"watchNamespaces":["team-a"],"image":{"repository":"private/operator","tag":"old","digest":"sha256:old"}},"ingress":{"host":"sync.example.com"}}';;
 *"get manifest"*) printf '%s\n' '# previous manifest';;
 *) printf '%s\n' '# rendered';;
esac
`
	kubectl := `#!/bin/sh
printf '%s\n' "kubectl $*" >> "$UPGRADE_LOG"
`
	for name, body := range map[string]string{"helm": helm, "kubectl": kubectl} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
	backup := filepath.Join(dir, "backup")
	args := []string{"--context", "test-context", "--release", "existing", "--namespace", "system", "--backup-dir", backup, "--dry-run"}
	if err := upgradeCluster(context.Background(), args); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(backup, "upgrade-values.json"))
	if err != nil {
		t.Fatal(err)
	}
	var values map[string]any
	json.Unmarshal(b, &values)
	op := values["operator"].(map[string]any)
	image := op["image"].(map[string]any)
	if image["repository"] != "private/operator" || image["tag"] != "1.2.3" || image["digest"] != "" || op["watchNamespaces"].([]any)[0] != "team-a" {
		t.Fatal(string(b))
	}
	b, _ = os.ReadFile(log)
	commands := string(b)
	if strings.Contains(commands, " upgrade ") || !strings.Contains(commands, "--dry-run=server") || !strings.Contains(commands, "--context test-context") {
		t.Fatal(commands)
	}
	if info, err := os.Stat(filepath.Join(backup, "previous-values.json")); err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("backup permissions", err)
	}
}

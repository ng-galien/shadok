package daemon

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path/filepath"
	"shadok.org/operator/internal/syncer"
	"strings"
	"time"
)

func LoadSession(ctx context.Context, d Destination, directory string) (Group, error) {
	transport, err := httpTransport(d.CAFile)
	if err != nil {
		return Group{}, err
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 30 * time.Second}
	endpoint := strings.TrimRight(d.URL, "/") + "/sessions/" + url.PathEscape(d.Namespace) + "/" + url.PathEscape(d.Session)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return Group{}, err
	}
	res, err := client.Do(req)
	if err != nil {
		return Group{}, err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return Group{}, fmt.Errorf("read session %s/%s: HTTP %d", d.Namespace, d.Session, res.StatusCode)
	}
	g := Group{Mode: "build"}
	if err := json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(&g); err != nil {
		return Group{}, err
	}
	if len(g.Roots) == 0 {
		return Group{}, fmt.Errorf("session %s has no directories with localPath", d.Session)
	}
	for i := range g.Roots {
		local := filepath.Clean(g.Roots[i].Path)
		if filepath.IsAbs(local) || local == ".." || strings.HasPrefix(local, ".."+string(filepath.Separator)) || !syncer.ValidMount(g.Roots[i].Mount) {
			return Group{}, fmt.Errorf("session output must be inside the project: %q", g.Roots[i].Path)
		}
		g.Roots[i].Path = filepath.Join(directory, local)
	}
	return g, nil
}

func ValidateSessionRoots(directory string, roots []syncer.Root) error {
	base, err := filepath.EvalSymlinks(directory)
	if err != nil {
		return err
	}
	for _, root := range roots {
		real, err := filepath.EvalSymlinks(root.Path)
		if err != nil {
			return fmt.Errorf("build output %s: %w", root.Path, err)
		}
		rel, err := filepath.Rel(base, real)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return fmt.Errorf("build output escapes project directory: %s", root.Path)
		}
	}
	return nil
}

// Package provision prepares verified tools in pod-local volumes before startup.
package provision

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"time"
)

type File struct {
	Directory string `json:"directory"`
	Path      string `json:"path"`
	URL       string `json:"url"`
	SHA256    string `json:"sha256"`
}

var namePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
var hashPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

func Validate(f File) error {
	u, err := url.Parse(f.URL)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || !namePattern.MatchString(f.Path) || !hashPattern.MatchString(f.SHA256) {
		return fmt.Errorf("invalid tool file %q: require filename, HTTPS URL and SHA256", f.Path)
	}
	return nil
}

func Prepare(ctx context.Context, files []File) error {
	c := &http.Client{Timeout: 2 * time.Minute, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if req.URL.Scheme != "https" || len(via) >= 10 {
			return fmt.Errorf("invalid tool redirect")
		}
		return nil
	}}
	for _, f := range files {
		slog.Info("tool preparation started", "file", f.Path, "directory", f.Directory)
		if err := download(ctx, c, f); err != nil {
			slog.Error("tool preparation failed", "file", f.Path, "directory", f.Directory, "error", err)
			return fmt.Errorf("prepare %s: %w", f.Path, err)
		}
		slog.Info("tool preparation completed", "file", f.Path, "directory", f.Directory)
	}
	return nil
}

func download(ctx context.Context, c *http.Client, f File) error {
	if err := Validate(f); err != nil {
		return err
	}
	if !filepath.IsAbs(f.Directory) {
		return fmt.Errorf("absolute destination required")
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, f.URL, nil)
	if err != nil {
		return err
	}
	response, err := c.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("download returned HTTP %d", response.StatusCode)
	}
	file, err := os.CreateTemp(f.Directory, ".shadok-download-")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	hash := sha256.New()
	const limit = 256 << 20
	n, err := io.Copy(io.MultiWriter(file, hash), io.LimitReader(response.Body, limit+1))
	if err != nil {
		return err
	}
	if n > limit {
		return fmt.Errorf("tool exceeds 256 MiB")
	}
	if hex.EncodeToString(hash.Sum(nil)) != f.SHA256 {
		return fmt.Errorf("SHA256 mismatch")
	}
	if err := file.Chmod(0444); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), filepath.Join(f.Directory, f.Path))
}

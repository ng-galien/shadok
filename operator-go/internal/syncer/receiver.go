package syncer

import (
	"archive/tar"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

type Ack struct {
	PodUID   string `json:"podUID,omitempty"`
	Revision string `json:"revision"`
	Epoch    string `json:"epoch"`
	Applied  bool   `json:"applied"`
}
type Plan struct {
	Epoch  string   `json:"epoch"`
	Needed []string `json:"needed"`
}
type Receiver struct {
	Roots        map[string]string
	Token, Epoch string
	mu           sync.Mutex
}

func NewReceiver(roots map[string]string, token string) *Receiver {
	b := make([]byte, 16)
	rand.Read(b)
	return &Receiver{Roots: roots, Token: token, Epoch: hex.EncodeToString(b)}
}
func (r *Receiver) ServeHTTP(w http.ResponseWriter, q *http.Request) {
	if r.Token != "" && subtle.ConstantTimeCompare([]byte(q.Header.Get("Authorization")), []byte("Bearer "+r.Token)) != 1 {
		slog.Warn("receiver request rejected", "path", q.URL.EscapedPath(), "status", 401)
		http.Error(w, "unauthorized", 401)
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	var result any
	var err error
	switch q.URL.Path {
	case "/plan":
		var m Manifest
		err = json.NewDecoder(io.LimitReader(q.Body, 8<<20)).Decode(&m)
		if err == nil {
			result, err = r.plan(m)
		}
	case "/apply":
		result, err = r.apply(q.Body)
	default:
		slog.Warn("receiver route not found", "path", q.URL.EscapedPath(), "status", 404)
		http.NotFound(w, q)
		return
	}
	if err != nil {
		slog.Error("receiver request failed", "path", q.URL.EscapedPath(), "error", err, "epoch", r.Epoch)
		http.Error(w, err.Error(), 400)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(result); err != nil {
		slog.Error("receiver response failed", "path", q.URL.EscapedPath(), "error", err)
	}
}
func (r *Receiver) validate(m Manifest) error {
	if len(m.Files) > MaxFiles || len(m.Roots) == 0 || ManifestHash(m) != m.Revision {
		return fmt.Errorf("invalid manifest")
	}
	roots := map[string]Root{}
	for _, root := range m.Roots {
		if _, ok := r.Roots[root.Mount]; !ok {
			return fmt.Errorf("unauthorized mount %q", root.Mount)
		}
		if _, ok := roots[root.Mount]; ok {
			return fmt.Errorf("duplicate mount")
		}
		roots[root.Mount] = root
	}
	seen := map[string]bool{}
	var total int64
	for _, e := range m.Files {
		parts := strings.SplitN(e.Name, "/", 2)
		if len(parts) != 2 || !ValidName(parts[1]) || strings.HasPrefix(parts[1], ".shadok-") || seen[e.Name] {
			return fmt.Errorf("invalid entry %q", e.Name)
		}
		root, ok := roots[parts[0]]
		if !ok || Excluded(parts[1], root.Exclude) {
			return fmt.Errorf("entry outside managed roots")
		}
		if e.Size < 0 || e.Size > MaxFileBytes || len(e.Hash) != 64 || e.Mode > 0777 {
			return fmt.Errorf("invalid file metadata")
		}
		total += e.Size
		seen[e.Name] = true
	}
	if total > MaxRevisionBytes {
		return fmt.Errorf("revision too large")
	}
	return nil
}
func (r *Receiver) current(m Manifest) (*Snapshot, error) {
	roots := []Root{}
	for _, root := range m.Roots {
		root.Path = r.Roots[root.Mount]
		root.Exclude = append(append([]string{}, root.Exclude...), ".shadok-*/**")
		roots = append(roots, root)
	}
	return Capture(roots, "")
}
func (r *Receiver) plan(m Manifest) (Plan, error) {
	p := Plan{Epoch: r.Epoch}
	if err := r.validate(m); err != nil {
		return p, err
	}
	current, err := r.current(m)
	if err != nil {
		return p, err
	}
	defer os.RemoveAll(current.Dir)
	hashes := map[string]Entry{}
	for _, e := range current.Manifest.Files {
		hashes[e.Name] = e
	}
	for _, e := range m.Files {
		old, ok := hashes[e.Name]
		if !ok || old.Hash != e.Hash || old.Mode != e.Mode {
			p.Needed = append(p.Needed, e.Name)
		}
	}
	slog.Info("receiver plan ready", "revision", m.Revision, "files", len(m.Files), "needed", len(p.Needed), "epoch", r.Epoch)
	return p, nil
}
func (r *Receiver) apply(body io.Reader) (Ack, error) {
	tr := tar.NewReader(io.LimitReader(body, MaxRevisionBytes+(32<<20)))
	h, err := tr.Next()
	if err != nil || h.Name != "manifest.json" || h.Size > 8<<20 {
		return Ack{}, fmt.Errorf("manifest must be first")
	}
	var m Manifest
	if err = json.NewDecoder(tr).Decode(&m); err != nil {
		return Ack{}, err
	}
	if err = r.validate(m); err != nil {
		return Ack{}, err
	}
	stage, err := os.MkdirTemp("", "shadok-receive-")
	if err != nil {
		return Ack{}, err
	}
	defer os.RemoveAll(stage)
	entries := map[string]Entry{}
	for _, e := range m.Files {
		entries[e.Name] = e
	}
	received := map[string]bool{}
	for {
		h, err = tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return Ack{}, err
		}
		e, ok := entries[h.Name]
		if !ok || received[h.Name] || h.Typeflag != tar.TypeReg || h.Size != e.Size {
			return Ack{}, fmt.Errorf("unexpected file")
		}
		target := filepath.Join(stage, filepath.FromSlash(h.Name))
		if err = os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			return Ack{}, err
		}
		f, err := os.Create(target)
		if err != nil {
			return Ack{}, err
		}
		hash, n, err := HashReader(io.TeeReader(tr, f))
		ce := f.Close()
		if err != nil {
			return Ack{}, err
		}
		if ce != nil {
			return Ack{}, ce
		}
		if hash != e.Hash || n != e.Size {
			return Ack{}, fmt.Errorf("content mismatch")
		}
		received[h.Name] = true
	}
	// Recheck actual state after upload. A stale plan cannot omit a changed file.
	plan, err := r.plan(m)
	if err != nil {
		return Ack{}, err
	}
	for _, name := range plan.Needed {
		if !received[name] {
			return Ack{}, fmt.Errorf("missing changed file %s; retry plan", name)
		}
	}
	for _, root := range m.Roots {
		fs, err := os.OpenRoot(r.Roots[root.Mount])
		if err != nil {
			return Ack{}, err
		}
		err = func() error {
			defer fs.Close()
			for _, e := range m.Files {
				if !strings.HasPrefix(e.Name, root.Mount+"/") || !received[e.Name] {
					continue
				}
				rel := strings.TrimPrefix(e.Name, root.Mount+"/")
				if err := fs.MkdirAll(filepath.Dir(rel), 0755); err != nil {
					return err
				}
				in, err := os.Open(filepath.Join(stage, filepath.FromSlash(e.Name)))
				if err != nil {
					return err
				}
				tmp := ".shadok-tmp-" + r.Epoch
				out, err := fs.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
				if err != nil {
					in.Close()
					return err
				}
				_, err = io.Copy(out, in)
				in.Close()
				ce := out.Close()
				if err != nil {
					return err
				}
				if ce != nil {
					return ce
				}
				if err = fs.Chmod(tmp, os.FileMode(e.Mode)); err != nil {
					return err
				}
				if err = fs.Rename(tmp, rel); err != nil {
					return err
				}
			}
			// Files only: retain empty directories so excluded descendants cannot be removed.
			return filepath.WalkDir(r.Roots[root.Mount], func(file string, d os.DirEntry, walkErr error) error {
				if walkErr != nil {
					return walkErr
				}
				rel, err := filepath.Rel(r.Roots[root.Mount], file)
				if err != nil {
					return err
				}
				rel = filepath.ToSlash(rel)
				if rel == "." {
					return nil
				}
				if strings.HasPrefix(rel, ".shadok-") {
					if d.IsDir() {
						return filepath.SkipDir
					}
					return nil
				}
				if Excluded(rel, root.Exclude) {
					if d.IsDir() {
						return filepath.SkipDir
					}
					return nil
				}
				if d.IsDir() {
					return nil
				}
				if _, ok := entries[root.Mount+"/"+rel]; !ok {
					return fs.Remove(rel)
				}
				return nil
			})
		}()
		if err != nil {
			return Ack{}, err
		}
	}
	slog.Info("receiver revision applied", "revision", m.Revision, "received", len(received), "files", len(m.Files), "epoch", r.Epoch)
	return Ack{Revision: m.Revision, Epoch: r.Epoch, Applied: true, PodUID: os.Getenv("SHADOK_POD_UID")}, nil
}

// Package syncer implements bounded whole-file, unidirectional revisions.
package syncer

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const MaxFiles = 20000
const MaxFileBytes int64 = 64 << 20
const MaxRevisionBytes int64 = 512 << 20

type Root struct {
	Mount    string   `json:"mount"`
	Path     string   `json:"path"`
	Exclude  []string `json:"exclude,omitempty"`
	Optional bool     `json:"optional,omitempty"`
}
type Entry struct {
	Name string `json:"name"`
	Hash string `json:"hash"`
	Size int64  `json:"size"`
	Mode uint32 `json:"mode"`
}
type Manifest struct {
	Revision string  `json:"revision"`
	Files    []Entry `json:"files"`
	Roots    []Root  `json:"roots"`
}
type Snapshot struct {
	Dir      string
	Manifest Manifest
}

func ValidName(s string) bool {
	return s != "" && s != "." && path.Clean(s) == s && !strings.HasPrefix(s, "/") && !strings.Contains(s, "\\") && s != ".." && !strings.HasPrefix(s, "../")
}
func ValidMount(s string) bool {
	return ValidName(s) && !strings.Contains(s, "/") && regexp.MustCompile(`^[a-z][a-z0-9-]*$`).MatchString(s)
}

// Glob exclusions use slash-separated paths; ** spans directories.
func Excluded(name string, patterns []string) bool {
	for _, p := range patterns {
		q := regexp.QuoteMeta(p)
		q = strings.ReplaceAll(q, `\*\*/`, `(?:.*/)?`)
		q = strings.ReplaceAll(q, `\*\*`, ".*")
		q = strings.ReplaceAll(q, `\*`, `[^/]*`)
		q = strings.ReplaceAll(q, `\?`, `[^/]`)
		re, err := regexp.Compile("^(?:" + q + ")$")
		if err == nil && re.MatchString(name) {
			return true
		}
	}
	return false
}
func HashReader(r io.Reader) (string, int64, error) {
	h := sha256.New()
	n, err := io.Copy(h, io.LimitReader(r, MaxFileBytes+1))
	if n > MaxFileBytes {
		return "", n, fmt.Errorf("file exceeds %d bytes", MaxFileBytes)
	}
	return hex.EncodeToString(h.Sum(nil)), n, err
}
func ManifestHash(m Manifest) string {
	m.Revision = ""
	b, _ := json.Marshal(m)
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}
func Capture(roots []Root, parent string) (*Snapshot, error) {
	dir, err := os.MkdirTemp(parent, "revision-")
	if err != nil {
		return nil, err
	}
	ok := false
	defer func() {
		if !ok {
			os.RemoveAll(dir)
		}
	}()
	m := Manifest{}
	seen := map[string]bool{}
	var total int64
	for _, r := range roots {
		if !ValidMount(r.Mount) || seen[r.Mount] {
			return nil, fmt.Errorf("invalid or duplicate mount %q", r.Mount)
		}
		seen[r.Mount] = true
		logical := r
		logical.Path = ""
		m.Roots = append(m.Roots, logical)
		info, e := os.Lstat(r.Path)
		if os.IsNotExist(e) && r.Optional {
			continue
		}
		if e != nil {
			return nil, e
		}
		if !info.IsDir() {
			return nil, fmt.Errorf("root must be a directory: %s", r.Path)
		}
		rootFS, openErr := os.OpenRoot(r.Path)
		if openErr != nil {
			return nil, openErr
		}
		err = filepath.WalkDir(r.Path, func(file string, d fs.DirEntry, e error) error {
			if e != nil {
				return e
			}
			rel, e := filepath.Rel(r.Path, file)
			if e != nil {
				return e
			}
			if rel == "." {
				return nil
			}
			rel = filepath.ToSlash(rel)
			if Excluded(rel, r.Exclude) {
				if d.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}
			if d.IsDir() {
				return nil
			}
			if !d.Type().IsRegular() {
				return fmt.Errorf("non-regular file refused: %s", file)
			}
			if len(m.Files) >= MaxFiles {
				return fmt.Errorf("too many files")
			}
			before, e := rootFS.Stat(rel)
			if e != nil {
				return e
			}
			in, e := rootFS.Open(rel)
			if e != nil {
				return e
			}
			defer in.Close()
			dest := filepath.Join(dir, r.Mount, filepath.FromSlash(rel))
			if e = os.MkdirAll(filepath.Dir(dest), 0755); e != nil {
				return e
			}
			out, e := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			if e != nil {
				return e
			}
			hash, n, e := HashReader(io.TeeReader(in, out))
			closeErr := out.Close()
			if e != nil {
				return e
			}
			if closeErr != nil {
				return closeErr
			}
			after, e := rootFS.Stat(rel)
			if e != nil {
				return e
			}
			if !os.SameFile(before, after) || before.Size() != after.Size() || !before.ModTime().Equal(after.ModTime()) || n != before.Size() {
				return fmt.Errorf("file changed during capture: %s", file)
			}
			total += n
			if total > MaxRevisionBytes {
				return fmt.Errorf("revision exceeds byte budget")
			}
			m.Files = append(m.Files, Entry{Name: r.Mount + "/" + rel, Hash: hash, Size: n, Mode: uint32(before.Mode().Perm() & 0777)})
			return nil
		})
		rootFS.Close()
		if err != nil {
			return nil, err
		}
	}
	sort.Slice(m.Roots, func(i, j int) bool { return m.Roots[i].Mount < m.Roots[j].Mount })
	sort.Slice(m.Files, func(i, j int) bool { return m.Files[i].Name < m.Files[j].Name })
	m.Revision = ManifestHash(m)
	ok = true
	return &Snapshot{Dir: dir, Manifest: m}, nil
}

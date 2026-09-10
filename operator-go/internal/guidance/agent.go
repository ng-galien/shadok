package guidance

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/sys/unix"
	"shadok.org/operator/internal/buildinfo"
)

const manifestName = ".shadok-managed.json"

type manifest struct {
	Version string            `json:"version"`
	Files   map[string]string `json:"files"`
}

func skillFiles() (map[string][]byte, error) {
	entry, err := topics.ReadFile("topics/SKILL.md")
	if err != nil {
		return nil, err
	}
	return map[string][]byte{"SKILL.md": entry}, nil
}
func hash(b []byte) string { sum := sha256.Sum256(b); return hex.EncodeToString(sum[:]) }

// physicalParents rejects symlinked installation paths rather than following them.
func physicalParents(path string) error {
	parent := filepath.Dir(path)
	if parent != path {
		if err := physicalParents(parent); err != nil {
			return err
		}
	}
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("path must contain physical directories, not links: %s", path)
	}
	return nil
}

// absolutePath recognizes macOS system aliases, while arbitrary user symlinks
// remain forbidden by physicalParents. Resolve only their known system targets.
func absolutePath(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	for _, alias := range []string{"/tmp", "/var"} {
		if abs == alias || strings.HasPrefix(abs, alias+"/") {
			if target, e := os.Readlink(alias); e == nil && (target == "private"+alias || target == "/private"+alias) {
				abs = "/private" + abs
			}
		}
	}
	return abs, nil
}

func SkillPath(client, path string) (string, error) {
	if client != "codex" && client != "claude" {
		return "", fmt.Errorf("unsupported client %q; use codex, claude or --path with the default client", client)
	}
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base := filepath.Join(home, "."+client)
		if client == "codex" && os.Getenv("CODEX_HOME") != "" {
			base = os.Getenv("CODEX_HOME")
		}
		path = filepath.Join(base, "skills", "shadok")
	}
	return absolutePath(path)
}

func loadVerified(path string) (manifest, error) {
	var m manifest
	if err := physicalParents(path); err != nil {
		return m, err
	}
	b, err := os.ReadFile(filepath.Join(path, manifestName))
	if err != nil {
		return m, fmt.Errorf("not a managed Shadok skill: %w", err)
	}
	if err = json.Unmarshal(b, &m); err != nil {
		return m, err
	}
	if m.Version == "" || len(m.Files) == 0 {
		return m, fmt.Errorf("invalid managed skill manifest")
	}
	seen := map[string]bool{}
	err = filepath.WalkDir(path, func(name string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, err := filepath.Rel(path, name)
		if err != nil {
			return err
		}
		if d.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("refusing symlink in managed skill: %s", rel)
		}
		if d.IsDir() {
			if rel == "." {
				return nil
			}
			// An empty foreign directory is user content too.
			for file := range m.Files {
				if strings.HasPrefix(file, rel+"/") {
					return nil
				}
			}
			return fmt.Errorf("unmanaged skill directory: %s", rel)
		}
		if !d.Type().IsRegular() {
			return fmt.Errorf("not a regular skill file: %s", rel)
		}
		if rel == manifestName {
			return nil
		}
		expected, ok := m.Files[filepath.ToSlash(rel)]
		if !ok {
			return fmt.Errorf("unmanaged skill file: %s", rel)
		}
		b, err := os.ReadFile(name)
		if err != nil {
			return err
		}
		if hash(b) != expected {
			return fmt.Errorf("modified skill file: %s", rel)
		}
		seen[filepath.ToSlash(rel)] = true
		return nil
	})
	if err != nil {
		return m, err
	}
	for name := range m.Files {
		if !seen[name] {
			return m, fmt.Errorf("missing skill file: %s", name)
		}
	}
	return m, nil
}

func SkillStatus(path string) (string, error) {
	if _, err := os.Lstat(path); os.IsNotExist(err) {
		return "not installed", nil
	}
	m, err := loadVerified(path)
	if err != nil {
		return "modified or unmanaged", err
	}
	files, err := skillFiles()
	if err != nil {
		return "", err
	}
	if m.Version != buildinfo.Version || len(files) != len(m.Files) {
		return "update available", nil
	}
	for name, b := range files {
		if m.Files[name] != hash(b) {
			return "update available", nil
		}
	}
	return "installed and current", nil
}

// ManageSkill serializes writers and refuses modified or foreign installations.
// The installer owns only its exact skill directory, never client configuration.
func ManageSkill(action, path string) (string, error) {
	path, err := absolutePath(path)
	if err != nil {
		return "", err
	}
	if action == "status" {
		return SkillStatus(path)
	}
	if action != "install" && action != "uninstall" {
		return "", fmt.Errorf("agent action must be install, status or uninstall")
	}
	parent := filepath.Dir(path)
	if err = physicalParents(parent); err != nil {
		return "", err
	}
	if action == "uninstall" {
		if _, err = os.Lstat(path); os.IsNotExist(err) {
			return "not installed", nil
		}
	}
	if err = os.MkdirAll(parent, 0755); err != nil {
		return "", err
	}
	// O_NOFOLLOW prevents an attacker-controlled lock symlink from being opened.
	fd, err := unix.Open(filepath.Join(parent, ".shadok-skill.lock"), unix.O_CREAT|unix.O_RDWR|unix.O_NOFOLLOW, 0600)
	if err != nil {
		return "", err
	}
	defer unix.Close(fd)
	if err = unix.Flock(fd, unix.LOCK_EX); err != nil {
		return "", err
	}
	defer unix.Flock(fd, unix.LOCK_UN)
	exists := false
	if _, err = os.Lstat(path); err == nil {
		exists = true
		if _, err = loadVerified(path); err != nil {
			return "", fmt.Errorf("refusing to change existing skill: %w", err)
		}
	} else if !os.IsNotExist(err) {
		return "", err
	}
	if action == "uninstall" {
		if !exists {
			return "not installed", nil
		}
		if err = os.RemoveAll(path); err != nil {
			return "", err
		}
		return "uninstalled", nil
	}
	if exists {
		status, err := SkillStatus(path)
		if err != nil {
			return "", err
		}
		if status == "installed and current" {
			return status, nil
		}
	}
	files, err := skillFiles()
	if err != nil {
		return "", err
	}
	stage, err := os.MkdirTemp(parent, ".shadok-skill-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(stage)
	m := manifest{Version: buildinfo.Version, Files: map[string]string{}}
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		target := filepath.Join(stage, name)
		if err = os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return "", err
		}
		if err = os.WriteFile(target, files[name], 0644); err != nil {
			return "", err
		}
		m.Files[name] = hash(files[name])
	}
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return "", err
	}
	if err = os.WriteFile(filepath.Join(stage, manifestName), b, 0644); err != nil {
		return "", err
	}
	if err = os.Chmod(stage, 0755); err != nil {
		return "", err
	}
	if exists {
		backup, err := os.MkdirTemp(parent, ".shadok-backup-")
		if err != nil {
			return "", err
		}
		if err = os.Remove(backup); err != nil {
			return "", err
		}
		if err = renameNew(path, backup); err != nil {
			os.Remove(backup)
			return "", err
		}
		if err = renameNew(stage, path); err != nil {
			if restoreErr := renameNew(backup, path); restoreErr != nil {
				return "", fmt.Errorf("install failed: %v; previous skill retained at %s (restore failed: %v)", err, backup, restoreErr)
			}
			return "", err
		}
		if err = os.RemoveAll(backup); err != nil {
			return "", err
		}
	} else {
		if err = renameNew(stage, path); err != nil {
			return "", err
		}
	}
	return "installed", nil
}

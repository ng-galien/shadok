package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	semver "k8s.io/apimachinery/pkg/util/version"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"syscall"
	"time"

	"shadok.org/operator/internal/buildinfo"
	"shadok.org/operator/internal/guidance"
)

var releaseVersion = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$`)

func upgrade(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: shadok upgrade cli|cluster [OPTIONS]; see shadok learn upgrade")
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	switch args[0] {
	case "cli":
		return upgradeCLI(ctx, args[1:])
	case "cluster":
		return upgradeCluster(ctx, args[1:])
	default:
		return fmt.Errorf("unknown upgrade target %q; use cli or cluster", args[0])
	}
}
func fetch(ctx context.Context, url string, limit int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "shadok-upgrade")
	response, err := (&http.Client{Timeout: 2 * time.Minute}).Do(req)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download %s: %s", url, response.Status)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, fmt.Errorf("download exceeds size limit")
	}
	return data, nil
}
func releaseBinary(ctx context.Context, base, version string) ([]byte, error) {
	name := fmt.Sprintf("shadok_%s_%s_%s.tar.gz", version, runtime.GOOS, runtime.GOARCH)
	sums, err := fetch(ctx, base+"/SHA256SUMS-"+version, 1<<20)
	if err != nil {
		return nil, err
	}
	digest := ""
	for _, line := range strings.Split(string(sums), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 2 && strings.TrimPrefix(fields[1], "*") == name {
			if digest != "" {
				return nil, fmt.Errorf("duplicate checksum")
			}
			digest = fields[0]
		}
	}
	if len(digest) != 64 {
		return nil, fmt.Errorf("missing SHA256 for %s", name)
	}
	archive, err := fetch(ctx, base+"/"+name, 128<<20)
	if err != nil {
		return nil, err
	}
	actual := sha256.Sum256(archive)
	if hex.EncodeToString(actual[:]) != strings.ToLower(digest) {
		return nil, fmt.Errorf("SHA256 mismatch; installed CLI unchanged")
	}
	reader, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	tr := tar.NewReader(io.LimitReader(reader, 300<<20))
	var binary []byte
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if h.Name != "shadok" {
			continue
		}
		if binary != nil || h.Typeflag != tar.TypeReg || h.Size <= 0 || h.Size > 256<<20 {
			return nil, fmt.Errorf("invalid binary archive entry")
		}
		binary, err = io.ReadAll(io.LimitReader(tr, (256<<20)+1))
		if err != nil {
			return nil, err
		}
	}
	if len(binary) == 0 {
		return nil, fmt.Errorf("release archive has no shadok binary")
	}
	return binary, nil
}
func upgradeCLI(ctx context.Context, args []string) error {
	f := flag.NewFlagSet("upgrade cli", flag.ContinueOnError)
	version := f.String("version", "latest", "published version, or latest stable release")
	output := f.String("output", "", "installation path (default: current executable)")
	if err := f.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if f.NArg() != 0 {
		return fmt.Errorf("unexpected arguments")
	}
	v := strings.TrimPrefix(*version, "v")
	if v == "latest" {
		data, err := fetch(ctx, "https://api.github.com/repos/ng-galien/shadok/releases/latest", 1<<20)
		if err != nil {
			return err
		}
		var release struct {
			Tag string `json:"tag_name"`
		}
		if err = json.Unmarshal(data, &release); err != nil {
			return err
		}
		v = strings.TrimPrefix(release.Tag, "v")
	}
	if !releaseVersion.MatchString(v) {
		return fmt.Errorf("invalid release version %q", v)
	}
	if *version == "latest" && *output == "" {
		current, currentErr := semver.ParseSemantic(buildinfo.Version)
		available, availableErr := semver.ParseSemantic(v)
		if currentErr == nil && availableErr == nil && current.AtLeast(available) {
			fmt.Printf("CLI %s is already at least the latest published version %s.\n", buildinfo.Version, v)
			return nil
		}
	}
	target := *output
	if target == "" {
		var err error
		target, err = os.Executable()
		if err != nil {
			return err
		}
		target, err = filepath.EvalSymlinks(target)
		if err != nil {
			return err
		}
	}
	target, err := filepath.Abs(target)
	if err != nil {
		return err
	}
	if info, err := os.Lstat(target); err == nil && !info.Mode().IsRegular() {
		return fmt.Errorf("target must be a regular file: %s", target)
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	data, err := releaseBinary(ctx, "https://github.com/ng-galien/shadok/releases/download/v"+v, v)
	if err != nil {
		return err
	}
	staged, err := os.CreateTemp(filepath.Dir(target), ".shadok-upgrade-*")
	if err != nil {
		return err
	}
	name := staged.Name()
	defer os.Remove(name)
	if _, err = staged.Write(data); err != nil {
		staged.Close()
		return err
	}
	if err = staged.Chmod(0755); err != nil {
		staged.Close()
		return err
	}
	if err = staged.Sync(); err != nil {
		staged.Close()
		return err
	}
	if err = staged.Close(); err != nil {
		return err
	}
	check, err := exec.CommandContext(ctx, name, "version").Output()
	if err != nil {
		return fmt.Errorf("downloaded CLI cannot run: %w", err)
	}
	if strings.TrimSpace(string(check)) != v {
		return fmt.Errorf("downloaded CLI version differs from release")
	}
	// Only the verified binary reaches the atomic replacement step.
	if err = os.Rename(name, target); err != nil {
		return err
	}
	fmt.Printf("CLI %s installed at %s (SHA256 verified). Cluster unchanged.\n", v, target)
	fmt.Println("If a daemon is running, run 'shadok daemon stop', then restart your build/watch command.")
	return nil
}

func upgradeCluster(ctx context.Context, args []string) error {
	f := flag.NewFlagSet("upgrade cluster", flag.ContinueOnError)
	contextName := f.String("context", "", "required Kubernetes context")
	release := f.String("release", "shadok", "existing Helm release")
	namespace := f.String("namespace", "shadok-system", "Helm release namespace")
	values := f.String("values", "", "additional Helm values file")
	backup := f.String("backup-dir", "", "new directory for saved values and manifests (default: private temporary directory)")
	timeout := f.Duration("timeout", 5*time.Minute, "Helm rollout timeout")
	dry := f.Bool("dry-run", false, "render and validate without modifying cluster resources")
	if err := f.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if f.NArg() != 0 {
		return fmt.Errorf("unexpected arguments")
	}
	if *contextName == "" {
		return fmt.Errorf("--context is required")
	}
	if !releaseVersion.MatchString(buildinfo.Version) {
		return fmt.Errorf("cluster upgrade requires a versioned release CLI")
	}
	if *timeout <= 0 {
		return fmt.Errorf("--timeout must be positive")
	}
	for _, tool := range []string{"helm", "kubectl"} {
		if _, err := exec.LookPath(tool); err != nil {
			return err
		}
	}
	run := func(tool string, a ...string) ([]byte, error) {
		cmd := exec.CommandContext(ctx, tool, a...)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		b, err := cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("%s failed: %w\n%s\n%s", tool, err, b, stderr.String())
		}
		if stderr.Len() > 0 {
			fmt.Fprint(os.Stderr, stderr.String())
		}
		return b, nil
	}
	helm := []string{"--kube-context", *contextName, "--namespace", *namespace}
	// Read the existing release; never implicitly install a different release.
	previous, err := run("helm", append(append([]string{}, helm...), "get", "values", *release, "-o", "json")...)
	if err != nil {
		return err
	}
	manifest, err := run("helm", append(append([]string{}, helm...), "get", "manifest", *release)...)
	if err != nil {
		return err
	}
	dir := *backup
	if dir == "" {
		dir, err = os.MkdirTemp("", "shadok-upgrade-")
	} else {
		dir, err = filepath.Abs(dir)
		if err == nil {
			err = os.Mkdir(dir, 0700)
		}
	}
	if err != nil {
		return err
	}
	fmt.Println("Upgrade backup:", dir)
	if err = os.WriteFile(filepath.Join(dir, "previous-values.json"), previous, 0600); err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(dir, "previous-manifest.yaml"), manifest, 0600); err != nil {
		return err
	}
	var configured map[string]any
	if err = json.Unmarshal(previous, &configured); err != nil {
		return err
	}
	if configured == nil {
		configured = map[string]any{}
	}
	// Keep repositories and operational values; advance the three runtime images.
	for _, path := range [][]string{{"operator", "image"}, {"operator", "toolImage"}, {"gateway", "image"}} {
		section, _ := configured[path[0]].(map[string]any)
		if section == nil {
			section = map[string]any{}
			configured[path[0]] = section
		}
		image, _ := section[path[1]].(map[string]any)
		if image == nil {
			image = map[string]any{}
			section[path[1]] = image
		}
		image["tag"] = buildinfo.Version
		image["digest"] = ""
	}
	upgradeValues, _ := json.Marshal(configured)
	valuePath := filepath.Join(dir, "upgrade-values.json")
	if err = os.WriteFile(valuePath, upgradeValues, 0600); err != nil {
		return err
	}
	chart := filepath.Join(dir, "chart")
	if err = guidance.ExportChart(chart); err != nil {
		return err
	}
	opts := []string{"-f", valuePath}
	if *values != "" {
		opts = append(opts, "-f", *values)
	}
	if _, err = run("helm", append([]string{"lint", chart, "--strict"}, opts...)...); err != nil {
		return err
	}
	rendered, err := run("helm", append([]string{"template", *release, chart, "--namespace", *namespace}, opts...)...)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(dir, "rendered.yaml"), rendered, 0600); err != nil {
		return err
	}
	crd := filepath.Join(chart, "crds", "shadok.org_developmentsessions.yaml")
	kube := []string{"--context", *contextName, "apply", "-f", crd}
	if *dry {
		kube = append(kube, "--dry-run=server")
	}
	if _, err = run("kubectl", kube...); err != nil {
		return fmt.Errorf("CRD update: %w", err)
	}
	if *dry {
		fmt.Println("Dry run completed; no cluster resources changed.")
		return nil
	}
	command := append(append([]string{}, helm...), "upgrade", *release, chart, "--reset-values", "--wait", "--timeout", timeout.String())
	command = append(command, opts...)
	out, err := run("helm", command...)
	if err != nil {
		return fmt.Errorf("CRD applied; Helm upgrade failed. Backup retained at %s: %w", dir, err)
	}
	fmt.Print(string(out))
	fmt.Printf("Cluster release %s/%s upgraded to %s. Backup: %s\n", *namespace, *release, buildinfo.Version, dir)
	return nil
}

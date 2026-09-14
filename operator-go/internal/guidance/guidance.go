// Package guidance provides version-matched offline operational documentation.
package guidance

import (
	"embed"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	assets "shadok.org/operator"
	"shadok.org/operator/internal/buildinfo"
	"sigs.k8s.io/yaml"
)

//go:embed topics/*.md
var topics embed.FS

var topicNames = []string{"learn", "spring", "quarkus", "node", "python", "install", "network", "upgrade", "lifecycle", "inspect", "configure", "builds", "verify", "chart"}

const Help = `Shadok: live development for existing Kubernetes Deployments

Usage: shadok COMMAND [OPTIONS]

Offline guidance (no daemon, network or cluster access):
  help, --help, -h            Show this command reference
  learn [TOPIC]              Agent onboarding, or a specific operational topic
  docs [TOPIC]               spring, quarkus, node, python, install, network, upgrade, lifecycle,
                            inspect, configure, builds, verify, chart,
                            values, schema, crd, all (default: topic index)
  chart export DIRECTORY    Export the complete embedded Helm chart to a new directory
  agent install|status|uninstall [--client codex|claude] [--path DIRECTORY]
                            Manage the embedded skill (default client: codex)
  version, --version        Show the embedded build version

Upgrade commands:
  upgrade cli [--version VERSION] [--output PATH]
                            Verify and install a published CLI (default: latest)
  upgrade cluster --context CONTEXT [--release NAME] [--namespace NAME]
                  [--values FILE] [--backup-dir DIRECTORY] [--dry-run]
                            Upgrade an existing installation to this CLI version

Development commands:
  watch                     Start continuous source synchronization
  publish                   Snapshot completed outputs and wait for revision ACK
  build [OPTIONS] -- CMD...  Run a successful build, snapshot outputs, then publish
  status                    Show all local daemon jobs as JSON
  unwatch                   Remove the matching job and its retained snapshot
  daemon serve|stop         Run the daemon foreground, or stop all local jobs

Options for watch/publish/build/unwatch:
  --session NAMESPACE/NAME  Read source/output mappings from the DevelopmentSession
  --config FILE             Optional legacy local project YAML
  --group NAME              Group only when using --config
  --destination NAME        Personal destination (default: SHADOK_DESTINATION)
  --url URL                 Sync gateway origin, including http(s)://
  --namespace NAME          Existing application namespace
  --deployment NAME         Existing application Deployment
  --ca-file FILE            Additional trusted PEM CA certificate
  --timeout DURATION        Initial confirmation timeout (default: 1m)
  --receiver-url URL        Direct receiver URL for local tests only
  --token-file FILE          Optional direct local-test receiver token

Environment:
  SHADOK_DESTINATIONS        Personal destination YAML path (OS user config by default)
  SHADOK_STATE_DIR           Private daemon directory (OS user cache by default)

Container plumbing:
  install DESTINATION       Copy this executable (used by the tool init container)
  seed --roots JSON         Seed configured directories in the application image
  receive --roots JSON [--listen ADDRESS] [--token-file FILE]
                            Start the in-pod receiver (default: 127.0.0.1:7777)

Run 'shadok learn' for the complete installation-to-restoration workflow.
`

// ChartFile reads canonical chart assets, applying only release identity fields.
func ChartFile(name string) ([]byte, error) {
	b, err := assets.Chart.ReadFile("chart/" + name)
	if err != nil {
		return nil, err
	}
	if buildinfo.Version == "dev" {
		return b, nil
	}
	if name == "values.yaml" && buildinfo.ImagePrefix != "" {
		for _, component := range []string{"operator", "gateway", "tools"} {
			b = []byte(strings.ReplaceAll(string(b), "repository: shadok-"+component+",", "repository: "+buildinfo.ImagePrefix+"/"+component+","))
		}
	}
	if name == "Chart.yaml" {
		var data map[string]any
		if err := yaml.Unmarshal(b, &data); err != nil {
			return nil, err
		}
		data["version"], data["appVersion"] = buildinfo.Version, buildinfo.Version
		return yaml.Marshal(data)
	}
	return b, nil
}

func Document(topic string) ([]byte, error) {
	switch topic {
	case "chart":
		return ChartFile("README.md")
	case "values":
		return ChartFile("values.yaml")
	case "schema":
		return ChartFile("values.schema.json")
	case "crd":
		return ChartFile("crds/shadok.org_developmentsessions.yaml")
	case "all":
		var out []byte
		for _, name := range topicNames {
			b, err := Document(name)
			if err != nil {
				return nil, err
			}
			out = append(out, b...)
			out = append(out, '\n')
		}
		return out, nil
	}
	for _, name := range topicNames {
		if topic == name {
			return topics.ReadFile("topics/" + topic + ".md")
		}
	}
	return nil, fmt.Errorf("unknown documentation topic %q; available: learn, spring, quarkus, node, python, install, network, upgrade, lifecycle, inspect, configure, builds, verify, chart, values, schema, crd, all", topic)
}

func Print(w io.Writer, topic string) error {
	b, err := Document(topic)
	if err != nil {
		return err
	}
	_, err = w.Write(b)
	return err
}

// ExportChart only creates a new directory and never overwrites an existing path.
func ExportChart(path string) error {
	if path == "" {
		return fmt.Errorf("chart export requires a destination directory")
	}
	abs, err := absolutePath(path)
	if err != nil {
		return err
	}
	if err = physicalParents(filepath.Dir(abs)); err != nil {
		return err
	}
	if _, err = os.Lstat(abs); !os.IsNotExist(err) {
		return fmt.Errorf("chart destination already exists or is inaccessible: %s", abs)
	}
	stage, err := os.MkdirTemp(filepath.Dir(abs), ".shadok-chart-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	err = fs.WalkDir(assets.Chart, "chart", func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel := strings.TrimPrefix(path, "chart")
		rel = strings.TrimPrefix(rel, "/")
		target := filepath.Join(stage, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		b, err := ChartFile(rel)
		if err != nil {
			return err
		}
		return os.WriteFile(target, b, 0644)
	})
	if err != nil {
		return err
	}
	// Kernel-enforced no-replace rename protects overlapping exports.
	return renameNew(stage, abs)
}

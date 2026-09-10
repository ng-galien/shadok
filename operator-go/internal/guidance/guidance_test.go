package guidance

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"shadok.org/operator/internal/buildinfo"
	"shadok.org/operator/internal/daemon"
	"sigs.k8s.io/yaml"
)

func physicalTemp(t *testing.T) string {
	t.Helper()
	p, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestOfflineChartExportAndReleaseIdentity(t *testing.T) {
	oldV, oldP := buildinfo.Version, buildinfo.ImagePrefix
	t.Cleanup(func() { buildinfo.Version, buildinfo.ImagePrefix = oldV, oldP })
	buildinfo.Version, buildinfo.ImagePrefix = "1.2.3", "registry.example.com/team"
	path := filepath.Join(physicalTemp(t), "chart")
	if err := ExportChart(path); err != nil {
		t.Fatal(err)
	}
	for _, file := range []string{"Chart.yaml", "values.yaml", "values.schema.json", "crds/shadok.org_developmentsessions.yaml", "templates/workloads.yaml", "templates/_helpers.tpl", ".helmignore"} {
		if _, err := os.Stat(filepath.Join(path, file)); err != nil {
			t.Fatal(err)
		}
	}
	b, _ := os.ReadFile(filepath.Join(path, "Chart.yaml"))
	var meta map[string]any
	if err := yaml.Unmarshal(b, &meta); err != nil {
		t.Fatal(err)
	}
	if meta["version"] != "1.2.3" || meta["appVersion"] != "1.2.3" {
		t.Fatalf("incorrect release identity: %s", b)
	}
	b, _ = os.ReadFile(filepath.Join(path, "values.yaml"))
	for _, component := range []string{"operator", "gateway", "tools"} {
		if !strings.Contains(string(b), "repository: registry.example.com/team/"+component+",") {
			t.Errorf("missing repository %s", component)
		}
	}
	if _, err := os.Stat(filepath.Join(path, ".DS_Store")); !os.IsNotExist(err) {
		t.Fatal("exported Finder metadata")
	}
	if err := ExportChart(path); err == nil {
		t.Fatal("overwrote existing chart")
	}
}

func TestSkillLifecyclePreservesForeignContent(t *testing.T) {
	path := filepath.Join(physicalTemp(t), "shadok")
	if _, err := ManageSkill("install", path); err != nil {
		t.Fatal(err)
	}
	if status, err := SkillStatus(path); err != nil || status != "installed and current" {
		t.Fatalf("%s %v", status, err)
	}
	if _, err := ManageSkill("install", path); err != nil {
		t.Fatal("idempotent install", err)
	}
	if err := os.WriteFile(filepath.Join(path, "SKILL.md"), []byte("personal changes"), 0644); err != nil {
		t.Fatal(err)
	}
	for _, action := range []string{"install", "uninstall"} {
		if _, err := ManageSkill(action, path); err == nil {
			t.Fatalf("%s ignored drift", action)
		}
	}
	b, _ := os.ReadFile(filepath.Join(path, "SKILL.md"))
	if string(b) != "personal changes" {
		t.Fatal("destroyed edits")
	}
}

func TestSkillUpdateAndUninstall(t *testing.T) {
	path := filepath.Join(physicalTemp(t), "shadok")
	old := buildinfo.Version
	t.Cleanup(func() { buildinfo.Version = old })
	buildinfo.Version = "1.0.0"
	if _, err := ManageSkill("install", path); err != nil {
		t.Fatal(err)
	}
	buildinfo.Version = "1.1.0"
	if status, err := SkillStatus(path); err != nil || status != "update available" {
		t.Fatalf("%s %v", status, err)
	}
	if _, err := ManageSkill("install", path); err != nil {
		t.Fatal(err)
	}
	if status, err := SkillStatus(path); err != nil || status != "installed and current" {
		t.Fatalf("%s %v", status, err)
	}
	if _, err := ManageSkill("uninstall", path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("skill remains", err)
	}
}

func TestSkillRejectsLinksAndForeignDirectories(t *testing.T) {
	base := physicalTemp(t)
	real := filepath.Join(base, "real")
	if err := os.Mkdir(real, 0755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "link")
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}
	if _, err := ManageSkill("install", filepath.Join(link, "shadok")); err == nil {
		t.Fatal("followed parent symlink")
	}
	if _, err := ManageSkill("install", real); err == nil {
		t.Fatal("claimed foreign directory")
	}
	path := filepath.Join(base, "skill")
	if _, err := ManageSkill("install", path); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(path, "personal"), 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := ManageSkill("uninstall", path); err == nil {
		t.Fatal("removed foreign empty directory")
	}
}

func TestDocumentsAndConfigurationExamples(t *testing.T) {
	for _, topic := range append(append([]string{}, topicNames...), "values", "schema", "crd", "all") {
		b, err := Document(topic)
		if err != nil || len(b) == 0 {
			t.Fatalf("%s: %v", topic, err)
		}
	}
	if _, err := Document("../../secrets"); err == nil {
		t.Fatal("accepted unknown topic")
	}
	// Parse portable group examples through the real runtime config loader.
	for _, topic := range []string{"configure", "builds"} {
		b, _ := Document(topic)
		chunks := strings.Split(string(b), "```yaml\n")
		found := 0
		for _, chunk := range chunks[1:] {
			snippet := strings.SplitN(chunk, "```", 2)[0]
			if !strings.Contains(snippet, "groups:") {
				continue
			}
			var cfg daemon.Config
			if err := yaml.UnmarshalStrict([]byte(snippet), &cfg); err != nil {
				t.Fatal(err)
			}
			file := filepath.Join(physicalTemp(t), "shadok.yaml")
			if err := os.WriteFile(file, []byte(snippet), 0644); err != nil {
				t.Fatal(err)
			}
			for group := range cfg.Groups {
				if _, _, err := daemon.Load(file, group); err != nil {
					t.Fatalf("%s example: %v", topic, err)
				}
			}
			found++
		}
		if found == 0 {
			t.Fatalf("no config in %s", topic)
		}
	}
}

func TestSkillMigratesVerifiedReferencesToMinimalRouter(t *testing.T) {
	path := filepath.Join(physicalTemp(t), "shadok")
	if _, err := ManageSkill("install", path); err != nil {
		t.Fatal(err)
	}
	// Model a previous managed install whose canonical reference hashes are valid.
	file := filepath.Join(path, "references", "install.md")
	if err := os.MkdirAll(filepath.Dir(file), 0755); err != nil {
		t.Fatal(err)
	}
	old := []byte("previous version's managed instructions")
	if err := os.WriteFile(file, old, 0644); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(path, manifestName)
	b, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	var m manifest
	if err = json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	m.Files["references/install.md"] = hash(old)
	b, err = json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(manifestPath, b, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err = ManageSkill("install", path); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected only SKILL.md and ownership manifest: %v", entries)
	}
	for _, entry := range entries {
		if entry.Name() != "SKILL.md" && entry.Name() != manifestName {
			t.Fatalf("unexpected installed content %s", entry.Name())
		}
	}
	if _, err = os.Stat(filepath.Join(path, "references")); !os.IsNotExist(err) {
		t.Fatal("old references retained", err)
	}
}

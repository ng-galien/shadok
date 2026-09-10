package daemon

import (
	"fmt"
	"os"
	"path/filepath"
	"shadok.org/operator/internal/syncer"
	"sigs.k8s.io/yaml"
)

type Group struct {
	Mode  string        `json:"mode"`
	Roots []syncer.Root `json:"roots"`
}
type Config struct {
	Version int              `json:"version"`
	Project string           `json:"project"`
	Groups  map[string]Group `json:"groups"`
}
type Destination struct {
	Deployment string `json:"deployment,omitempty"`
	Namespace  string `json:"namespace"`
	CAFile     string `json:"caFile,omitempty"`
	URL        string `json:"url,omitempty"`
	TokenFile  string `json:"tokenFile,omitempty"`
}

func Load(file, group string) (string, Group, error) {
	abs, err := filepath.Abs(file)
	if err != nil {
		return "", Group{}, err
	}
	b, err := os.ReadFile(abs)
	if err != nil {
		return "", Group{}, err
	}
	var c Config
	if err = yaml.UnmarshalStrict(b, &c); err != nil {
		return "", Group{}, err
	}
	g, ok := c.Groups[group]
	if !ok || len(g.Roots) == 0 || c.Version != 1 {
		return "", g, fmt.Errorf("config version 1 and nonempty group required")
	}
	if g.Mode != "watch" && g.Mode != "build" {
		return "", g, fmt.Errorf("mode must be watch or build")
	}
	for i := range g.Roots {
		if !filepath.IsAbs(g.Roots[i].Path) {
			g.Roots[i].Path = filepath.Join(filepath.Dir(abs), g.Roots[i].Path)
		}
	}
	return abs, g, nil
}
func LoadDestination(name string) (Destination, error) {
	file := os.Getenv("SHADOK_DESTINATIONS")
	if file == "" {
		h, _ := os.UserConfigDir()
		file = filepath.Join(h, "shadok", "destinations.yaml")
	}
	b, err := os.ReadFile(file)
	if err != nil {
		return Destination{}, err
	}
	var c struct {
		Version      int                    `json:"version"`
		Destinations map[string]Destination `json:"destinations"`
	}
	if err = yaml.UnmarshalStrict(b, &c); err != nil {
		return Destination{}, err
	}
	d, ok := c.Destinations[name]
	if !ok {
		return d, fmt.Errorf("unknown destination %q", name)
	}
	if d.CAFile != "" && !filepath.IsAbs(d.CAFile) {
		d.CAFile = filepath.Join(filepath.Dir(file), d.CAFile)
	}
	return d, nil
}

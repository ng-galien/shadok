// Package assets embeds canonical deployment assets for offline CLI operation.
package assets

import "embed"

// Chart is embedded directly from its maintained source; no generated copy.
//
//go:embed chart/Chart.yaml chart/LICENSE chart/values.yaml chart/values.schema.json chart/README.md chart/.helmignore chart/crds/*.yaml chart/templates/*.yaml chart/templates/*.tpl chart/templates/*.txt chart/templates/tests/*.yaml
var Chart embed.FS

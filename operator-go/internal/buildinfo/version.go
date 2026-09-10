package buildinfo

// Version is set by the release build. Development builds remain identifiable.
var Version = "dev"

// ImagePrefix identifies release container repositories for the embedded chart.
// Empty means source-chart defaults; no public registry is assumed.
var ImagePrefix string

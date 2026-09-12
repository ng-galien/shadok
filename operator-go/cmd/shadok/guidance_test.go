package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInformationalCommandsDoNotStartDaemon(t *testing.T) {
	state := filepath.Join(t.TempDir(), "state")
	t.Setenv("SHADOK_STATE_DIR", state)
	for _, args := range [][]string{{}, {"--help"}, {"learn"}, {"learn", "install"}, {"docs", "schema"}, {"version"}, {"watch", "--help"}, {"receive", "--help"}, {"agent", "install", "--help"}, {"upgrade", "cli", "--help"}, {"upgrade", "cluster", "--help"}, {"learn", "upgrade"}} {
		if err := run(args); err != nil {
			t.Errorf("%v: %v", args, err)
		}
	}
	for _, args := range [][]string{{"typo"}, {"docs", "missing"}, {"learn", "install", "extra"}} {
		if err := run(args); err == nil {
			t.Errorf("%v should fail", args)
		}
	}
	if _, err := os.Stat(state); !os.IsNotExist(err) {
		t.Fatalf("informational command created daemon state: %v", err)
	}
}

package syncer

import (
	"context"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestRevisionDiffDeletionAndReplacement(t *testing.T) {
	src, dst := t.TempDir(), t.TempDir()
	os.WriteFile(filepath.Join(src, "a"), []byte("one"), 0644)
	os.WriteFile(filepath.Join(dst, "baseline"), []byte("remove"), 0644)
	os.WriteFile(filepath.Join(dst, "keep.local"), []byte("keep"), 0644)
	roots := []Root{{Mount: "app", Path: src, Exclude: []string{"*.local"}}}
	s, err := Capture(roots, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(NewReceiver(map[string]string{"app": dst}, "token"))
	defer server.Close()
	ack, err := Send(context.Background(), server.Client(), server.URL, "token", s)
	if err != nil {
		t.Fatal(err)
	}
	if !ack.Applied {
		t.Fatal(ack)
	}
	if b, _ := os.ReadFile(filepath.Join(dst, "a")); string(b) != "one" {
		t.Fatal(string(b))
	}
	if _, e := os.Stat(filepath.Join(dst, "baseline")); !os.IsNotExist(e) {
		t.Fatal("baseline not deleted")
	}
	if _, e := os.Stat(filepath.Join(dst, "keep.local")); e != nil {
		t.Fatal("excluded file deleted")
	}
	// Same revision must heal changed receiver contents, not trust a cached ACK.
	os.WriteFile(filepath.Join(dst, "a"), []byte("corrupt"), 0644)
	if _, err = Send(context.Background(), server.Client(), server.URL, "token", s); err != nil {
		t.Fatal(err)
	}
	os.Remove(filepath.Join(src, "a"))
	os.WriteFile(filepath.Join(src, "b"), []byte("two"), 0755)
	next, err := Capture(roots, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if _, err = Send(context.Background(), server.Client(), server.URL, "token", next); err != nil {
		t.Fatal(err)
	}
	if _, e := os.Stat(filepath.Join(dst, "a")); !os.IsNotExist(e) {
		t.Fatal("deletion not applied")
	}
	if _, err = Send(context.Background(), server.Client(), server.URL, "wrong", next); err == nil {
		t.Fatal("authentication missing")
	}
	fresh := httptest.NewServer(NewReceiver(map[string]string{"app": t.TempDir()}, "token"))
	defer fresh.Close()
	newAck, err := Send(context.Background(), fresh.Client(), fresh.URL, "token", next)
	if err != nil {
		t.Fatal(err)
	}
	if newAck.Epoch == ack.Epoch {
		t.Fatal("epoch unchanged")
	}
}
func TestCaptureStableAndConfined(t *testing.T) {
	src := t.TempDir()
	os.WriteFile(filepath.Join(src, "a"), []byte("before"), 0644)
	s, err := Capture([]Root{{Mount: "app", Path: src}}, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(src, "a"), []byte("after"), 0644)
	b, _ := os.ReadFile(filepath.Join(s.Dir, "app/a"))
	if string(b) != "before" {
		t.Fatal("snapshot changed")
	}
	os.Symlink("/etc/passwd", filepath.Join(src, "escape"))
	if _, err = Capture([]Root{{Mount: "app", Path: src}}, t.TempDir()); err == nil {
		t.Fatal("symlink accepted")
	}
	for _, name := range []string{"../outside", "/absolute", "a/../../x", "a\\b"} {
		if ValidName(name) {
			t.Fatal(name)
		}
	}
}

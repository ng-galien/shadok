package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"golang.org/x/sys/unix"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"shadok.org/operator/internal/buildinfo"
	"shadok.org/operator/internal/daemon"
	"shadok.org/operator/internal/guidance"
	"shadok.org/operator/internal/syncer"
	"strings"
	"syscall"
	"time"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		fmt.Print(guidance.Help)
		return nil
	}
	if args[0] == "version" || args[0] == "--version" {
		fmt.Println(buildinfo.Version)
		return nil
	}

	switch args[0] {
	case "help", "--help", "-h":
		fmt.Print(guidance.Help)
		return nil
	case "learn", "docs":
		if len(args) > 2 {
			return fmt.Errorf("usage: shadok %s [TOPIC]", args[0])
		}
		topic := "learn"
		if len(args) == 2 {
			topic = args[1]
		}
		return guidance.Print(os.Stdout, topic)
	case "upgrade":
		return upgrade(args[1:])
	case "chart":
		if len(args) != 3 || args[1] != "export" {
			return fmt.Errorf("usage: shadok chart export DIRECTORY")
		}
		if err := guidance.ExportChart(args[2]); err != nil {
			return err
		}
		fmt.Println("Chart exported to", args[2])
		return nil
	case "agent":
		if len(args) < 2 {
			return fmt.Errorf("usage: shadok agent install|status|uninstall [--client codex|claude] [--path DIRECTORY]")
		}
		flags := flag.NewFlagSet("agent "+args[1], flag.ContinueOnError)
		client := flags.String("client", "codex", "agent client: codex or claude")
		path := flags.String("path", "", "exact skill directory (overrides client default)")
		if err := flags.Parse(args[2:]); err != nil {
			if errors.Is(err, flag.ErrHelp) {
				return nil
			}
			return err
		}
		if flags.NArg() != 0 {
			return fmt.Errorf("unexpected agent arguments: %v", flags.Args())
		}
		target, err := guidance.SkillPath(*client, *path)
		if err != nil {
			return err
		}
		status, err := guidance.ManageSkill(args[1], target)
		if err != nil {
			return err
		}
		fmt.Printf("%s: %s\n", target, status)
		return nil
	}
	// Reject unknown commands before starting a daemon or reading project files.
	switch args[0] {
	case "watch", "publish", "build", "status", "unwatch", "daemon", "receive", "seed", "install":
	default:
		return fmt.Errorf("unknown command %q; run shadok --help", args[0])
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	switch args[0] {
	case "daemon":
		if len(args) > 1 && args[1] == "serve" {
			return daemon.Serve(ctx, daemon.StateDir())
		}
		if len(args) > 1 && args[1] == "stop" {
			return ipc(ctx, "POST", "/stop", nil, nil)
		}
		return fmt.Errorf("daemon serve|stop")
	case "install":
		if len(args) != 2 {
			return fmt.Errorf("install destination required")
		}
		exe, err := os.Executable()
		if err != nil {
			return err
		}
		in, err := os.Open(exe)
		if err != nil {
			return err
		}
		defer in.Close()
		out, err := os.OpenFile(args[1], os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0755)
		if err != nil {
			return err
		}
		_, err = io.Copy(out, in)
		ce := out.Close()
		if err != nil {
			return err
		}
		return ce
	case "receive":
		f := flag.NewFlagSet("receive", flag.ContinueOnError)
		roots := f.String("roots", "", "JSON mount map")
		token := f.String("token-file", "", "token file")
		listen := f.String("listen", "127.0.0.1:7777", "loopback receiver address")
		if err := f.Parse(args[1:]); err != nil {
			if errors.Is(err, flag.ErrHelp) {
				return nil
			}
			return err
		}
		var r map[string]string
		if err := json.Unmarshal([]byte(*roots), &r); err != nil {
			return err
		}
		var b []byte
		if *token != "" {
			var err error
			b, err = os.ReadFile(*token)
			if err != nil {
				return err
			}
		}
		server := &http.Server{Addr: *listen, Handler: syncer.NewReceiver(r, strings.TrimSpace(string(b))), ReadHeaderTimeout: 10 * time.Second}
		go func() { <-ctx.Done(); server.Close() }()
		return server.ListenAndServe()
	case "seed":
		f := flag.NewFlagSet("seed", flag.ContinueOnError)
		raw := f.String("roots", "", "JSON source roots")
		if err := f.Parse(args[1:]); err != nil {
			if errors.Is(err, flag.ErrHelp) {
				return nil
			}
			return err
		}
		var roots []syncer.Root
		if err := json.Unmarshal([]byte(*raw), &roots); err != nil {
			return err
		}
		snap, err := syncer.Capture(roots, "")
		if err != nil {
			return err
		}
		defer os.RemoveAll(snap.Dir)
		for _, root := range roots {
			dest := "/shadok-seed/" + root.Mount
			marker := filepath.Join(dest, ".shadok-seeded")
			if _, err := os.Stat(marker); err == nil {
				continue
			}
			for _, e := range snap.Manifest.Files {
				if !strings.HasPrefix(e.Name, root.Mount+"/") {
					continue
				}
				rel := strings.TrimPrefix(e.Name, root.Mount+"/")
				target := filepath.Join(dest, rel)
				if err = os.MkdirAll(filepath.Dir(target), 0755); err != nil {
					return err
				}
				in, err := os.Open(filepath.Join(snap.Dir, e.Name))
				if err != nil {
					return err
				}
				out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, os.FileMode(e.Mode))
				if err != nil {
					in.Close()
					return err
				}
				_, err = io.Copy(out, in)
				in.Close()
				ce := out.Close()
				if err != nil {
					return err
				}
				if ce != nil {
					return ce
				}
			}
			if err = os.WriteFile(marker, []byte(snap.Manifest.Revision), 0600); err != nil {
				return err
			}
		}
		return nil
	}
	fs := flag.NewFlagSet(args[0], flag.ContinueOnError)
	config := fs.String("config", "shadok.yaml", "project configuration")
	group := fs.String("group", "", "logical group")
	destination := fs.String("destination", os.Getenv("SHADOK_DESTINATION"), "personal destination name")
	namespace := fs.String("namespace", "", "namespace")
	deployment := fs.String("deployment", "", "existing Deployment")
	syncURL := fs.String("url", "", "sync gateway origin, e.g. https://sync.example.com")
	caFile := fs.String("ca-file", "", "additional trusted PEM CA certificate")
	url := fs.String("receiver-url", "", "local-test receiver URL")
	tokenFile := fs.String("token-file", "", "local-test token path")
	timeout := fs.Duration("timeout", 60*time.Second, "confirmation timeout")
	if err := fs.Parse(args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if err := ensure(ctx); err != nil {
		return err
	}
	if args[0] == "status" {
		var jobs []json.RawMessage
		if err := ipc(ctx, "GET", "/jobs", nil, &jobs); err != nil {
			return err
		}
		b, _ := json.MarshalIndent(jobs, "", "  ")
		fmt.Println(string(b))
		return nil
	}
	abs, g, err := daemon.Load(*config, *group)
	if err != nil {
		return err
	}
	d := daemon.Destination{Namespace: *namespace, CAFile: *caFile, URL: *url, Deployment: *deployment, TokenFile: *tokenFile}
	if *destination != "" {
		d, err = daemon.LoadDestination(*destination)
		if err != nil {
			return err
		}
		if *namespace != "" {
			d.Namespace = *namespace
		}
	}
	if *caFile != "" {
		d.CAFile = *caFile
	}
	if d.CAFile != "" {
		d.CAFile, err = filepath.Abs(d.CAFile)
		if err != nil {
			return err
		}
	}
	if *syncURL != "" {
		d.URL = *syncURL
	}
	if *deployment != "" {
		d.Deployment = *deployment
	}
	if d.URL == "" {
		return fmt.Errorf("destination requires --url; Kubernetes credentials are not used by HTTP sync")
	}
	if d.TokenFile != "" {
		d.TokenFile, err = filepath.Abs(d.TokenFile)
		if err != nil {
			return err
		}
	}
	job := daemon.Job{Config: abs, Group: *group, Roots: g.Roots, Destination: d, Watch: args[0] == "watch"}
	job.ID = daemon.ID(abs, *group, d)
	if args[0] == "unwatch" {
		return ipc(ctx, "DELETE", "/jobs", &job, nil)
	}
	if args[0] != "publish" && args[0] != "watch" && args[0] != "build" {
		return fmt.Errorf("unknown command %s", args[0])
	}
	if job.Watch && g.Mode != "watch" {
		return fmt.Errorf("compiled groups require successful build notification, not watch")
	}
	if args[0] == "build" {
		cmdargs := fs.Args()
		if len(cmdargs) == 0 {
			return fmt.Errorf("build command required after --")
		}
		lock, err := os.OpenFile(filepath.Join(daemon.StateDir(), "build-"+daemon.ID(abs, "producer", daemon.Destination{})+".lock"), os.O_CREATE|os.O_RDWR, 0600)
		if err != nil {
			return err
		}
		defer lock.Close()
		if err = unix.Flock(int(lock.Fd()), unix.LOCK_EX); err != nil {
			return err
		}
		cmd := exec.CommandContext(ctx, cmdargs[0], cmdargs[1:]...)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err = cmd.Run(); err != nil {
			return fmt.Errorf("build failed; no revision published: %w", err)
		}
		job.Snapshot, err = syncer.Capture(g.Roots, daemon.StateDir())
		unix.Flock(int(lock.Fd()), unix.LOCK_UN)
		if err != nil {
			return err
		}
	} else {
		job.Snapshot, err = syncer.Capture(g.Roots, daemon.StateDir())
		if err != nil {
			return err
		}
	}
	if err = ipc(ctx, "POST", "/jobs", &job, nil); err != nil {
		os.RemoveAll(job.Snapshot.Dir)
		return err
	}
	deadline := time.Now().Add(*timeout)
	for time.Now().Before(deadline) {
		var jobs []*daemon.Job
		if err = ipc(ctx, "GET", "/jobs", nil, &jobs); err != nil {
			return err
		}
		for _, j := range jobs {
			if j.ID == job.ID && j.Ack.Applied && j.Ack.Revision == job.Snapshot.Manifest.Revision {
				fmt.Printf("applied revision=%s receiverEpoch=%s podUID=%s (application reload not verified)\n", j.Ack.Revision, j.Ack.Epoch, j.Ack.PodUID)
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(200 * time.Millisecond):
		}
	}
	return fmt.Errorf("confirmation timed out; snapshot retained and retries continue; inspect shadok status or unwatch")
}
func client() *http.Client {
	return &http.Client{Timeout: 55 * time.Second, Transport: &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", filepath.Join(daemon.StateDir(), "daemon.sock"))
	}}}
}
func ipc(ctx context.Context, method, path string, input, output any) error {
	b, _ := json.Marshal(input)
	r, err := http.NewRequestWithContext(ctx, method, "http://daemon"+path, bytes.NewReader(b))
	if err != nil {
		return err
	}
	res, err := client().Do(r)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		raw, _ := io.ReadAll(res.Body)
		return errors.New(string(raw))
	}
	if output != nil {
		return json.NewDecoder(res.Body).Decode(output)
	}
	return nil
}
func ensure(ctx context.Context) error {
	if ipc(ctx, "GET", "/health", nil, nil) == nil {
		return nil
	}
	dir := daemon.StateDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	log, err := os.OpenFile(filepath.Join(dir, "daemon.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer log.Close()
	cmd := exec.Command(exe, "daemon", "serve")
	cmd.Stdout = log
	cmd.Stderr = log
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err = cmd.Start(); err != nil {
		return err
	}
	cmd.Process.Release()
	for i := 0; i < 50; i++ {
		if ipc(ctx, "GET", "/health", nil, nil) == nil {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("daemon did not start; inspect %s", filepath.Join(dir, "daemon.log"))
}

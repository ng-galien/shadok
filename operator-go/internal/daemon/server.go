package daemon

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"golang.org/x/sys/unix"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"shadok.org/operator/internal/syncer"
	"sync"
	"time"
)

type Job struct {
	ID             string           `json:"id"`
	Config         string           `json:"config"`
	Group          string           `json:"group"`
	Roots          []syncer.Root    `json:"roots"`
	Destination    Destination      `json:"destination"`
	Watch          bool             `json:"watch"`
	Snapshot       *syncer.Snapshot `json:"snapshot"`
	Ack            syncer.Ack       `json:"ack"`
	Error          string           `json:"error,omitempty"`
	Updated        time.Time        `json:"updated"`
	mu             sync.Mutex
	inFlight       *syncer.Snapshot
	cancelDelivery context.CancelFunc
}
type Server struct {
	Dir  string
	mu   sync.Mutex
	jobs map[string]*Job
}

func ID(config, group string, d Destination) string {
	b, _ := json.Marshal([]any{config, group, d})
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:16])
}
func StateDir() string {
	if d := os.Getenv("SHADOK_STATE_DIR"); d != "" {
		return d
	}
	d, _ := os.UserCacheDir()
	return filepath.Join(d, "shadok")
}
func Serve(ctx context.Context, dir string) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(filepath.Join(dir, "daemon.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = unix.Flock(int(lock.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		return fmt.Errorf("daemon already running")
	}
	socket := filepath.Join(dir, "daemon.sock")
	os.Remove(socket)
	l, err := net.Listen("unix", socket)
	if err != nil {
		return err
	}
	defer l.Close()
	os.Chmod(socket, 0600)
	s := &Server{Dir: dir, jobs: map[string]*Job{}}
	files, _ := filepath.Glob(filepath.Join(dir, "job-*.json"))
	for _, f := range files {
		b, e := os.ReadFile(f)
		if e != nil {
			continue
		}
		j := &Job{}
		if json.Unmarshal(b, j) == nil && j.ID != "" {
			s.jobs[j.ID] = j
			go s.loop(ctx, j)
		}
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/stop", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "stopping")
		go func() { time.Sleep(50 * time.Millisecond); cancel() }()
	})
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "shadok-daemon-v1") })
	mux.HandleFunc("/jobs", func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		if r.Method != "GET" && r.Method != "POST" && r.Method != "DELETE" {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if r.Method == "GET" {
			out := []json.RawMessage{}
			for _, j := range s.jobs {
				j.mu.Lock()
				b, _ := json.Marshal(j)
				j.mu.Unlock()
				out = append(out, b)
			}
			json.NewEncoder(w).Encode(out)
			return
		}
		var incoming Job
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<20)).Decode(&incoming); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if incoming.ID != ID(incoming.Config, incoming.Group, incoming.Destination) {
			http.Error(w, "invalid ID", 400)
			return
		}
		if r.Method == "DELETE" {
			if j := s.jobs[incoming.ID]; j != nil {
				j.mu.Lock()
				j.Watch = false
				replaceSnapshot(j, nil)
				j.mu.Unlock()
				delete(s.jobs, j.ID)
				os.Remove(filepath.Join(s.Dir, "job-"+j.ID+".json"))
			}
			return
		}
		if s.jobs[incoming.ID] == nil && len(s.jobs) >= 8 {
			http.Error(w, "at most 8 active groups per daemon", 400)
			return
		}
		existing := s.jobs[incoming.ID]
		if existing != nil {
			existing.mu.Lock()
			replaceSnapshot(existing, incoming.Snapshot)
			existing.Roots = incoming.Roots
			existing.Destination = incoming.Destination
			existing.Watch = existing.Watch || incoming.Watch
			existing.Error = ""
			existing.Ack = syncer.Ack{}
			s.save(existing)
			existing.mu.Unlock()
		} else {
			s.jobs[incoming.ID] = &incoming
			s.save(&incoming)
			go s.loop(ctx, &incoming)
		}
		json.NewEncoder(w).Encode(map[string]string{"id": incoming.ID})
	})
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() { <-ctx.Done(); server.Close() }()
	return server.Serve(l)
}
func (s *Server) save(j *Job) {
	b, _ := json.Marshal(j)
	p := filepath.Join(s.Dir, "job-"+j.ID+".json")
	if os.WriteFile(p+".tmp", b, 0600) == nil {
		os.Rename(p+".tmp", p)
	}
}
func (s *Server) loop(ctx context.Context, j *Job) {
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		j.mu.Lock()
		if !j.Watch && j.Snapshot == nil {
			j.mu.Unlock()
			return
		}
		scanError := ""
		if j.Watch {
			snap, err := syncer.Capture(j.Roots, s.Dir)
			if err != nil {
				scanError = err.Error()
			} else if j.Snapshot != nil && j.Snapshot.Manifest.Revision == snap.Manifest.Revision {
				os.RemoveAll(snap.Dir)
			} else {
				replaceSnapshot(j, snap)
			}
		}
		if j.Snapshot != nil {
			snapshot, destination := j.Snapshot, j.Destination
			sendCtx, cancel := context.WithTimeout(ctx, 45*time.Second)
			j.inFlight = snapshot
			j.cancelDelivery = cancel
			j.mu.Unlock()
			ack, err := Deliver(sendCtx, destination, snapshot)
			cancel()
			j.mu.Lock()
			j.inFlight = nil
			j.cancelDelivery = nil
			if j.Snapshot == snapshot {
				if err != nil {
					j.Error = err.Error()
				} else {
					j.Ack = ack
					j.Error = ""
				}
				if scanError != "" {
					j.Error = "source scan: " + scanError
				}
				j.Updated = time.Now()
				s.save(j)
			} else {
				os.RemoveAll(snapshot.Dir)
			}
		}
		j.mu.Unlock()
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
		}
	}
}

// Caller holds j.mu. In-flight snapshots remain readable until delivery finishes.
func replaceSnapshot(j *Job, next *syncer.Snapshot) {
	old := j.Snapshot
	j.Snapshot = next
	if old != nil && old != next {
		if old != j.inFlight {
			os.RemoveAll(old.Dir)
		}
		if j.cancelDelivery != nil {
			j.cancelDelivery()
		}
	}
}

// Package gateway routes sync to a DevelopmentSession and its live receivers.
package gateway

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/util/validation"
	"net/http"
	"os"
	api "shadok.org/operator/api/v1alpha1"
	"shadok.org/operator/internal/syncer"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sort"
	"strings"
	"time"
)

type Target struct{ UID, URL string }
type Resolver interface {
	Resolve(context.Context, string, string) ([]Target, error)
}
type KubernetesResolver struct {
	Reader     client.Reader
	Namespaces map[string]bool
}

func (k KubernetesResolver) Resolve(ctx context.Context, ns, deployment string) ([]Target, error) {
	if len(k.Namespaces) > 0 && !k.Namespaces[ns] {
		return nil, fmt.Errorf("namespace outside configured scope")
	}
	sessions := &api.DevelopmentSessionList{}
	if err := k.Reader.List(ctx, sessions, client.InNamespace(ns)); err != nil {
		return nil, err
	}
	var session *api.DevelopmentSession
	for i := range sessions.Items {
		if sessions.Items[i].Spec.Deployment == deployment && sessions.Items[i].Spec.Enabled && sessions.Items[i].DeletionTimestamp.IsZero() {
			if session != nil {
				return nil, fmt.Errorf("ambiguous Deployment configuration")
			}
			session = &sessions.Items[i]
		}
	}
	if session == nil {
		return nil, fmt.Errorf("target not configured or not live")
	}
	return k.targets(ctx, session)
}

func (k KubernetesResolver) Session(ctx context.Context, ns, name string) (*api.DevelopmentSession, error) {
	if len(k.Namespaces) > 0 && !k.Namespaces[ns] {
		return nil, fmt.Errorf("namespace outside configured scope")
	}
	s := &api.DevelopmentSession{}
	if err := k.Reader.Get(ctx, client.ObjectKey{Namespace: ns, Name: name}, s); err != nil {
		return nil, err
	}
	if !s.Spec.Enabled || !s.DeletionTimestamp.IsZero() {
		return nil, fmt.Errorf("session is not live")
	}
	return s, nil
}

func (k KubernetesResolver) ResolveSession(ctx context.Context, ns, name string) ([]Target, error) {
	s, err := k.Session(ctx, ns, name)
	if err != nil {
		return nil, err
	}
	return k.targets(ctx, s)
}

func (k KubernetesResolver) targets(ctx context.Context, session *api.DevelopmentSession) ([]Target, error) {
	if !session.Spec.Enabled || !session.DeletionTimestamp.IsZero() {
		return nil, fmt.Errorf("target is not live")
	}
	pods := &corev1.PodList{}
	if err := k.Reader.List(ctx, pods, client.InNamespace(session.Namespace), client.MatchingLabels{"shadok.org/session": string(session.UID)}); err != nil {
		return nil, err
	}
	targets := []Target{}
	for _, p := range pods.Items {
		if !p.DeletionTimestamp.IsZero() || p.Status.PodIP == "" || p.Annotations["shadok.org/live-session"] != string(session.UID) {
			continue
		}
		ready := false
		for _, condition := range p.Status.Conditions {
			if condition.Type == corev1.PodReady && condition.Status == corev1.ConditionTrue {
				ready = true
			}
		}
		if !ready {
			continue
		}
		running := false
		for _, c := range p.Status.ContainerStatuses {
			if c.Name == "shadok-sync" && c.State.Running != nil {
				running = true
			}
		}
		if running {
			targets = append(targets, Target{UID: string(p.UID), URL: "http://" + p.Status.PodIP + ":7777"})
		}
	}
	if len(targets) == 0 {
		return nil, fmt.Errorf("no live receiver available")
	}
	sort.Slice(targets, func(i, j int) bool { return targets[i].UID < targets[j].UID })
	return targets, nil
}

type Handler struct {
	Resolver Resolver
	Client   *http.Client
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	var targets []Target
	var err error
	if len(parts) >= 3 && parts[0] == "sessions" && !(len(parts) == 3 && r.Method == http.MethodPost) {
		resolver, ok := h.Resolver.(interface {
			Session(context.Context, string, string) (*api.DevelopmentSession, error)
			ResolveSession(context.Context, string, string) ([]Target, error)
		})
		if !ok || len(validation.IsDNS1123Label(parts[1])) != 0 || len(validation.IsDNS1123Subdomain(parts[2])) != 0 {
			http.NotFound(w, r)
			return
		}
		if len(parts) == 3 && r.Method == "GET" {
			session, e := resolver.Session(r.Context(), parts[1], parts[2])
			if e != nil {
				http.Error(w, e.Error(), 409)
				return
			}
			roots := []syncer.Root{}
			for _, d := range session.Spec.Directories {
				if d.LocalPath != "" {
					roots = append(roots, syncer.Root{Mount: d.Name, Path: d.LocalPath, Exclude: d.Exclude})
				}
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(struct {
				Roots []syncer.Root `json:"roots"`
			}{roots})
			return
		}
		if len(parts) != 4 || r.Method != "POST" || (parts[3] != "plan" && parts[3] != "apply") {
			http.NotFound(w, r)
			return
		}
		targets, err = resolver.ResolveSession(r.Context(), parts[1], parts[2])
		parts = []string{parts[1], parts[2], parts[3]}
	} else {
		if r.Method != "POST" {
			http.Error(w, "POST required", 405)
			return
		}
		if len(parts) != 3 || len(validation.IsDNS1123Label(parts[0])) != 0 || len(validation.IsDNS1123Subdomain(parts[1])) != 0 || (parts[2] != "plan" && parts[2] != "apply") {
			http.NotFound(w, r)
			return
		}
		targets, err = h.Resolver.Resolve(r.Context(), parts[0], parts[1])
	}
	if err != nil {
		http.Error(w, err.Error(), 409)
		return
	}
	limit := syncer.MaxRevisionBytes + (32 << 20)
	if parts[2] == "plan" {
		limit = 8 << 20
	}
	f, err := os.CreateTemp("", "shadok-gateway-")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer os.Remove(f.Name())
	defer f.Close()
	n, err := io.Copy(f, io.LimitReader(r.Body, limit+1))
	if err != nil {
		http.Error(w, "cannot buffer request: "+err.Error(), 500)
		return
	}
	if n > limit {
		http.Error(w, "request exceeds limit", 413)
		return
	}
	client := h.Client
	if client == nil {
		client = &http.Client{Timeout: 45 * time.Second}
	}
	epochs := []string{}
	needed := map[string]bool{}
	revision := ""
	for _, target := range targets {
		if _, err = f.Seek(0, 0); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		q, err := http.NewRequestWithContext(r.Context(), "POST", target.URL+"/"+parts[2], io.NopCloser(f))
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		q.ContentLength = n
		res, err := client.Do(q)
		if err != nil {
			http.Error(w, "receiver unavailable; retry revision", 503)
			return
		}
		if res.StatusCode != 200 {
			res.Body.Close()
			http.Error(w, "receiver rejected revision", 502)
			return
		}
		if parts[2] == "plan" {
			var p syncer.Plan
			err = json.NewDecoder(io.LimitReader(res.Body, 8<<20)).Decode(&p)
			epochs = append(epochs, target.UID+":"+p.Epoch)
			for _, name := range p.Needed {
				needed[name] = true
			}
		} else {
			var ack syncer.Ack
			err = json.NewDecoder(io.LimitReader(res.Body, 8<<20)).Decode(&ack)
			if !ack.Applied || (revision != "" && revision != ack.Revision) {
				err = fmt.Errorf("inconsistent revision ACK")
			}
			revision = ack.Revision
			epochs = append(epochs, target.UID+":"+ack.Epoch)
		}
		res.Body.Close()
		if err != nil {
			http.Error(w, "invalid receiver response", 502)
			return
		}
	}
	sort.Strings(epochs)
	digest := sha256.Sum256([]byte(strings.Join(epochs, "\n")))
	epoch := hex.EncodeToString(digest[:])
	w.Header().Set("Content-Type", "application/json")
	if parts[2] == "plan" {
		p := syncer.Plan{Epoch: epoch}
		for name := range needed {
			p.Needed = append(p.Needed, name)
		}
		sort.Strings(p.Needed)
		json.NewEncoder(w).Encode(p)
	} else {
		json.NewEncoder(w).Encode(syncer.Ack{Revision: revision, Epoch: epoch, Applied: true})
	}
}

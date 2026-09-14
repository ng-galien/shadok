package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"net/http/httptest"
	"os"
	"path/filepath"
	api "shadok.org/operator/api/v1alpha1"
	"shadok.org/operator/internal/syncer"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"testing"
)

func TestSessionDescriptionUsesResourceNameAndOnlyDeclaredOutputs(t *testing.T) {
	scheme := runtime.NewScheme()
	api.AddToScheme(scheme)
	s := &api.DevelopmentSession{ObjectMeta: metav1.ObjectMeta{Name: "live", Namespace: "team"}, Spec: api.SessionSpec{Enabled: true, Deployment: "different-deployment", Directories: []api.Directory{{Name: "packaged", ImagePath: "/app", MountPath: "/live/app"}, {Name: "classes", MountPath: "/live/classes", LocalPath: "target/classes"}}}}
	reader := fake.NewClientBuilder().WithScheme(scheme).WithObjects(s).Build()
	h := httptest.NewServer(&Handler{Resolver: KubernetesResolver{Reader: reader, Namespaces: map[string]bool{"team": true}}})
	defer h.Close()
	res, err := h.Client().Get(h.URL + "/sessions/team/live")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var result struct {
		Roots []syncer.Root `json:"roots"`
	}
	if err := json.NewDecoder(res.Body).Decode(&result); err != nil {
		t.Fatal(err)
	}
	if len(result.Roots) != 1 || result.Roots[0].Mount != "classes" || result.Roots[0].Path != "target/classes" {
		t.Fatalf("unexpected outputs: %+v", result)
	}
	for _, route := range []string{"/sessions/team/different-deployment", "/sessions/other/live"} {
		res, err := h.Client().Get(h.URL + route)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode == 200 {
			t.Fatalf("unexpected resolution of %s", route)
		}
	}
	s.Spec.Enabled = false
	reader.Update(context.Background(), s)
	res, err = h.Client().Get(h.URL + "/sessions/team/live")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode == 200 {
		t.Fatal("disabled session accepted")
	}
}

type resolverFunc func(context.Context, string, string) ([]Target, error)

func (f resolverFunc) Resolve(ctx context.Context, ns, dep string) ([]Target, error) {
	return f(ctx, ns, dep)
}
func TestRoutesFanoutAndReplacement(t *testing.T) {
	roots := []string{t.TempDir(), t.TempDir(), t.TempDir()}
	servers := []*httptest.Server{}
	for _, root := range roots {
		receiver := syncer.NewReceiver(map[string]string{"app": root}, "")
		srv := httptest.NewServer(receiver)
		defer srv.Close()
		servers = append(servers, srv)
	}
	targets := []Target{{UID: "one", URL: servers[0].URL}, {UID: "two", URL: servers[1].URL}}
	gateway := httptest.NewServer(&Handler{Resolver: resolverFunc(func(_ context.Context, ns, dep string) ([]Target, error) {
		if (ns != "team" && ns != "sessions") || dep != "app" {
			return nil, fmt.Errorf("not configured")
		}
		return targets, nil
	})})
	defer gateway.Close()
	src := t.TempDir()
	os.WriteFile(filepath.Join(src, "file"), []byte("revision"), 0600)
	snap, err := syncer.Capture([]syncer.Root{{Mount: "app", Path: src}}, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(snap.Dir)
	send := func(path string) error {
		_, err := syncer.Send(context.Background(), gateway.Client(), gateway.URL+path, "", snap)
		return err
	}
	if err := send("/team/app"); err != nil {
		t.Fatal(err)
	}
	if err := send("/sessions/app"); err != nil {
		t.Fatalf("legacy namespace named sessions must remain routable: %v", err)
	}
	for _, root := range roots[:2] {
		b, err := os.ReadFile(filepath.Join(root, "file"))
		if err != nil || string(b) != "revision" {
			t.Fatal("fanout failed", err)
		}
	}
	if err := send("/other/app"); err == nil {
		t.Fatal("cross-namespace accepted")
	}
	if err := send("/team/missing"); err == nil {
		t.Fatal("missing target accepted")
	}
	targets = []Target{{UID: "replacement", URL: servers[2].URL}}
	if err := send("/team/app"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(roots[2], "file")); err != nil {
		t.Fatal("replacement not restored")
	}
}

func TestResolverWaitsForPodReadiness(t *testing.T) {
	scheme := runtime.NewScheme()
	corev1.AddToScheme(scheme)
	api.AddToScheme(scheme)
	session := &api.DevelopmentSession{ObjectMeta: metav1.ObjectMeta{Name: "live", Namespace: "team", UID: "session"}, Spec: api.SessionSpec{Enabled: true, Deployment: "app"}}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "app-pod", Namespace: "team", UID: "pod", Labels: map[string]string{"shadok.org/session": "session", "shadok.org/live-deployment": "app"}, Annotations: map[string]string{"shadok.org/live-session": "session"}}, Status: corev1.PodStatus{PodIP: "10.0.0.1", ContainerStatuses: []corev1.ContainerStatus{{Name: "shadok-sync", State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{}}}}}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(pod).WithObjects(session, pod).Build()
	resolver := KubernetesResolver{Reader: c}
	if _, err := resolver.Resolve(context.Background(), "team", "app"); err == nil {
		t.Fatal("not-ready application accepted")
	}
	pod.Status.Conditions = []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}
	if err := c.Status().Update(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if targets, err := resolver.Resolve(context.Background(), "team", "app"); err != nil || len(targets) != 1 {
		t.Fatal("ready pod not routed", err)
	}
	otherSession := session.DeepCopy()
	otherSession.Namespace = "other"
	otherSession.ResourceVersion = ""
	otherSession.UID = "other-session"
	if err := c.Create(context.Background(), otherSession); err != nil {
		t.Fatal(err)
	}
	otherPod := pod.DeepCopy()
	otherPod.Namespace = "other"
	otherPod.ResourceVersion = ""
	otherPod.UID = "other-pod"
	otherPod.Labels = map[string]string{"shadok.org/session": "other-session"}
	otherPod.Annotations = map[string]string{"shadok.org/live-session": "other-session"}
	otherPod.Status.PodIP = "10.0.0.2"
	if err := c.Create(context.Background(), otherPod); err != nil {
		t.Fatal(err)
	}
	for ns, want := range map[string]string{"team": "http://10.0.0.1:7777", "other": "http://10.0.0.2:7777"} {
		targets, err := resolver.Resolve(context.Background(), ns, "app")
		if err != nil || len(targets) != 1 || targets[0].URL != want {
			t.Fatalf("namespace %s not isolated: %v %v", ns, targets, err)
		}
	}
	session.Spec.Enabled = false
	c.Update(context.Background(), session)
	if _, err := resolver.Resolve(context.Background(), "team", "app"); err == nil {
		t.Fatal("inactive target accepted")
	}
}

func TestNamespaceScopeRejectsBeforeKubernetesAccess(t *testing.T) {
	resolver := KubernetesResolver{Namespaces: map[string]bool{"allowed": true}}
	if _, err := resolver.Resolve(context.Background(), "other", "app"); err == nil {
		t.Fatal("out-of-scope namespace accepted")
	}
}

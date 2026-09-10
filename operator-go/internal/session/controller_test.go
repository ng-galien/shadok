package session

import (
	"context"
	"encoding/json"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"reflect"
	api "shadok.org/operator/api/v1alpha1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"testing"
)

func fixture(t *testing.T) (*Reconciler, *api.DevelopmentSession, *appsv1.Deployment) {
	t.Helper()
	scheme := runtime.NewScheme()
	corev1.AddToScheme(scheme)
	appsv1.AddToScheme(scheme)
	api.AddToScheme(scheme)
	d := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: "app", Namespace: "test", UID: "deployment-1"}, Spec: appsv1.DeploymentSpec{Replicas: ptr(int32(3)), Template: corev1.PodTemplateSpec{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{"app": "existing"}}, Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "app", Image: "baseline", Env: []corev1.EnvVar{{Name: "KEEP", Value: "yes"}}}}}}}}
	s := &api.DevelopmentSession{ObjectMeta: metav1.ObjectMeta{Name: "live", Namespace: "test", UID: "session-1", Generation: 1}, Spec: api.SessionSpec{Enabled: true, Deployment: "app", Container: "app", RunAsUser: 1000, RunAsGroup: 1000, Directories: []api.Directory{{Name: "app", ImagePath: "/app", MountPath: "/app"}}, Start: api.Start{Command: []string{"run"}}}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(s).WithObjects(d, s).Build()
	return &Reconciler{Client: c, ToolImage: "tools"}, s, d
}
func TestEnableRestorePreservesDeployment(t *testing.T) {
	r, s, d := fixture(t)
	ctx := context.Background()
	original := d.DeepCopy()
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if len(d.Spec.Template.Spec.Containers) != 2 || d.Spec.Template.Labels["app"] != "existing" || *d.Spec.Replicas != 3 {
		t.Fatal("live transformation lost routing or replicas")
	}
	if err := r.enable(ctx, s); err != nil {
		t.Fatal("idempotence", err)
	}
	if err := r.restore(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if !reflect.DeepEqual(d.Spec, original.Spec) {
		a, _ := json.Marshal(d.Spec)
		t.Fatalf("baseline not restored: %s", a)
	}
	if err := r.restore(ctx, s); err != nil {
		t.Fatal(err)
	}
}
func TestExternalChangeIsNotOverwritten(t *testing.T) {
	r, s, d := fixture(t)
	ctx := context.Background()
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	d.Spec.Template.Spec.Containers[0].Image = "external-upgrade"
	r.Update(ctx, d)
	if err := r.restore(ctx, s); err == nil {
		t.Fatal("external change silently overwritten")
	}
	if err := r.enable(ctx, s); err == nil {
		t.Fatal("external live change silently accepted")
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if d.Spec.Template.Spec.Containers[0].Image != "external-upgrade" {
		t.Fatal("external image lost")
	}
}
func TestConflictingSessionRejected(t *testing.T) {
	r, s, _ := fixture(t)
	other := s.DeepCopy()
	other.Name = "other"
	other.UID = "session-2"
	other.ResourceVersion = ""
	if err := r.Create(context.Background(), other); err != nil {
		t.Fatal(err)
	}
	if err := r.enable(context.Background(), s); err == nil {
		t.Fatal("two writers accepted")
	}
}

func TestDeletingSessionRestoresBeforeFinalizerRemoval(t *testing.T) {
	r, s, d := fixture(t)
	ctx := context.Background()
	original := d.DeepCopy()
	request := ctrl.Request{NamespacedName: client.ObjectKeyFromObject(s)}
	for i := 0; i < 2; i++ {
		if _, err := r.Reconcile(ctx, request); err != nil {
			t.Fatal(err)
		}
	}
	if err := r.Get(ctx, request.NamespacedName, s); err != nil {
		t.Fatal(err)
	}
	if len(s.Finalizers) != 1 {
		t.Fatal("missing restoration finalizer")
	}
	if err := r.Delete(ctx, s); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if !reflect.DeepEqual(original.Spec, d.Spec) {
		t.Fatal("deleted session left live template")
	}
	if err := r.Get(ctx, request.NamespacedName, &api.DevelopmentSession{}); !apierrors.IsNotFound(err) {
		t.Fatal("finalizer not released", err)
	}
}

type interruptedClient struct {
	client.Client
	failRecord bool
	racePatch  bool
}

func (c *interruptedClient) Update(ctx context.Context, obj client.Object, opts ...client.UpdateOption) error {
	if cm, ok := obj.(*corev1.ConfigMap); ok && c.failRecord && cm.Data["appliedTemplate"] != "" {
		c.failRecord = false
		return fmt.Errorf("simulated interruption recording applied template")
	}
	return c.Client.Update(ctx, obj, opts...)
}
func (c *interruptedClient) Patch(ctx context.Context, obj client.Object, patch client.Patch, opts ...client.PatchOption) error {
	options := &client.PatchOptions{}
	options.ApplyOptions(opts)
	if d, ok := obj.(*appsv1.Deployment); ok && c.racePatch && len(options.DryRun) == 0 {
		c.racePatch = false
		external := &appsv1.Deployment{}
		if err := c.Client.Get(ctx, client.ObjectKeyFromObject(d), external); err != nil {
			return err
		}
		external.Spec.Template.Spec.Containers[0].Image = "external-concurrent-change"
		if err := c.Client.Update(ctx, external); err != nil {
			return err
		}
	}
	return c.Client.Patch(ctx, obj, patch, opts...)
}
func TestInterruptedApplyCanRestoreFromWriteAheadIntent(t *testing.T) {
	r, s, d := fixture(t)
	original := d.DeepCopy()
	r.Client = &interruptedClient{Client: r.Client, failRecord: true}
	if err := r.enable(context.Background(), s); err == nil {
		t.Fatal("interruption not simulated")
	}
	if err := r.restore(context.Background(), s); err != nil {
		t.Fatal("intent did not allow recovery", err)
	}
	r.Get(context.Background(), client.ObjectKeyFromObject(d), d)
	if !reflect.DeepEqual(original.Spec, d.Spec) {
		t.Fatal("baseline lost")
	}
}
func TestConcurrentDeploymentChangeConflicts(t *testing.T) {
	r, s, d := fixture(t)
	r.Client = &interruptedClient{Client: r.Client, racePatch: true}
	if err := r.enable(context.Background(), s); !apierrors.IsConflict(err) {
		t.Fatal("expected optimistic conflict", err)
	}
	r.Get(context.Background(), client.ObjectKeyFromObject(d), d)
	if d.Spec.Template.Spec.Containers[0].Image != "external-concurrent-change" {
		t.Fatal("concurrent change overwritten")
	}
}
func TestMissingBaselineIsNotReportedAsRestored(t *testing.T) {
	r, s, _ := fixture(t)
	ctx := context.Background()
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	cm, err := r.baseline(ctx, s)
	if err != nil {
		t.Fatal(err)
	}
	r.Delete(ctx, cm)
	if err := r.restore(ctx, s); err == nil {
		t.Fatal("missing baseline silently accepted")
	}
}

func TestCustomImageRestoredAndUninstallGuard(t *testing.T) {
	r, s, d := fixture(t)
	ctx := context.Background()
	original := d.DeepCopy()
	if err := CheckUninstall(ctx, r.Client, nil); err == nil {
		t.Fatal("active session allowed uninstall")
	}
	s.Spec.Image = "team/live:2"
	s.Spec.ImagePullPolicy = "Always"
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	if err := r.restore(ctx, s); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(d), d); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(original.Spec, d.Spec) {
		t.Fatal("custom live image was not restored")
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(s), s); err != nil {
		t.Fatal(err)
	}
	s.Spec.Enabled = false
	s.Finalizers = []string{finalizer}
	if err := r.Update(ctx, s); err != nil {
		t.Fatal(err)
	}
	if err := CheckUninstall(ctx, r.Client, nil); err == nil {
		t.Fatal("pending restoration allowed uninstall")
	}
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: client.ObjectKeyFromObject(s)}); err != nil {
		t.Fatal(err)
	}
	if err := CheckUninstall(ctx, r.Client, nil); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(s), s); err != nil {
		t.Fatal(err)
	}
	if len(s.Finalizers) != 0 {
		t.Fatal("restored session retains finalizer")
	}
}

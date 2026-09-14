package session

import (
	"context"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"reflect"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"testing"
)

func TestTemplatePatchLifecycle(t *testing.T) {
	r, s, d := fixture(t)
	d.Spec.Selector = &metav1.LabelSelector{MatchLabels: map[string]string{"app": "existing"}}
	d.Spec.Template.Spec.Containers[0].LivenessProbe = &corev1.Probe{ProbeHandler: corev1.ProbeHandler{Exec: &corev1.ExecAction{Command: []string{"true"}}}}
	d.Spec.Template.Spec.Containers[0].Resources = corev1.ResourceRequirements{Limits: corev1.ResourceList{corev1.ResourceMemory: resource.MustParse("512Mi")}}
	d.Spec.Template.Spec.Containers = append(d.Spec.Template.Spec.Containers, corev1.Container{Name: "platform-sidecar", Image: "sidecar"})
	ctx := context.Background()
	if err := r.Update(ctx, d); err != nil {
		t.Fatal(err)
	}
	original := d.DeepCopy()
	s.Spec.PodTemplatePatch = `{"spec":{"containers":[{"name":"app","livenessProbe":null,"resources":{"requests":{"cpu":"500m"}},"env":[{"name":"LIVE","value":"yes"}]}],"terminationGracePeriodSeconds":45}}`
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	app := d.Spec.Template.Spec.Containers[0]
	if app.LivenessProbe != nil || app.Resources.Requests.Cpu().String() != "500m" || app.Resources.Limits.Memory().String() != "512Mi" || len(app.Env) != 2 || len(d.Spec.Template.Spec.Containers) != 3 {
		t.Fatalf("lost fields or failed patch: %+v", app)
	}
	s.Generation++
	s.Spec.PodTemplatePatch = `{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"750m"}}}]}}`
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if d.Spec.Template.Spec.Containers[0].LivenessProbe == nil || d.Spec.Template.Spec.Containers[0].Resources.Requests.Cpu().String() != "750m" || len(d.Spec.Template.Spec.Containers[0].Env) != 1 {
		t.Fatal("new patch accumulated previous overrides")
	}
	s.Generation++
	s.Spec.PodTemplatePatch = ""
	if err := r.enable(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if len(d.Spec.Template.Spec.Containers[0].Resources.Requests) != 0 {
		t.Fatal("removed patch retained CPU override")
	}
	if err := r.restore(ctx, s); err != nil {
		t.Fatal(err)
	}
	r.Get(ctx, client.ObjectKeyFromObject(d), d)
	if !reflect.DeepEqual(d.Spec, original.Spec) {
		t.Fatal("baseline not restored exactly")
	}
}

func TestTemplatePatchRejectsInvalidTemplate(t *testing.T) {
	_, s, d := fixture(t)
	d.Spec.Selector = &metav1.LabelSelector{MatchLabels: map[string]string{"app": "existing"}}
	for _, patch := range []string{`{"spec":{"unknown":true}}`, `{"metadata":{"labels":{"app":null}}}`, `{"spec":{"containers":[{"name":"app","$patch":"delete"}]}}`, `{"spec":{"containers":[{"name":"shadok-sync","image":"other"}]}}`} {
		s.Spec.PodTemplatePatch = patch
		if _, err := Plan(s, d, "tools"); err == nil {
			t.Fatalf("invalid patch accepted: %s", patch)
		}
	}
}

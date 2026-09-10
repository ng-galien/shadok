package session

import (
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"reflect"
	api "shadok.org/operator/api/v1alpha1"
	"testing"
)

func TestPlanPreservesAndSeeds(t *testing.T) {
	d := &appsv1.Deployment{Spec: appsv1.DeploymentSpec{Template: corev1.PodTemplateSpec{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{"app": "production"}, Annotations: map[string]string{"platform.example/setting": "preserved"}}, Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "sidecar", Image: "original"}, {Name: "app", Image: "baseline", Env: []corev1.EnvVar{{Name: "CONFIG", Value: "preserve"}}, VolumeMounts: []corev1.VolumeMount{{Name: "secret", MountPath: "/secret"}}}}, Volumes: []corev1.Volume{{Name: "secret", VolumeSource: corev1.VolumeSource{Secret: &corev1.SecretVolumeSource{SecretName: "secret"}}}}}}}}
	s := &api.DevelopmentSession{ObjectMeta: metav1.ObjectMeta{Name: "demo", Namespace: "test", Generation: 1}, Spec: api.SessionSpec{Container: "app", RunAsUser: 1000, RunAsGroup: 1000, Start: api.Start{Command: []string{"live"}, Args: []string{"arg"}}, Directories: []api.Directory{{Name: "app", ImagePath: "/app", MountPath: "/app"}}}}
	before := d.DeepCopy()
	p, err := Plan(s, d, "tools")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(d, before) {
		t.Fatal("source mutated")
	}
	if p.Annotations["platform.example/setting"] != "preserved" {
		t.Fatal("application annotation lost")
	}
	if p.Labels["app"] != "production" {
		t.Fatal("Deployment routing label lost")
	}
	if !reflect.DeepEqual(p.Spec.Containers[0], d.Spec.Template.Spec.Containers[0]) {
		t.Fatal("sidecar changed")
	}
	if p.Spec.Containers[1].Env[0].Value != "preserve" {
		t.Fatal("env lost")
	}
	seed := p.Spec.InitContainers[1]
	if seed.Image != "baseline" || seed.VolumeMounts[1].MountPath != "/shadok-seed/app" {
		t.Fatal("seed masks source")
	}
	for _, m := range seed.VolumeMounts {
		if m.Name == "secret" {
			t.Fatal("secret exposed to seed")
		}
	}
	s.Spec.Directories[0].MountPath = "/secret/child"
	if _, err = Plan(s, d, "tools"); err == nil {
		t.Fatal("collision accepted")
	}
}

func TestCustomLiveImageSeedsFromOverride(t *testing.T) {
	d := &appsv1.Deployment{Spec: appsv1.DeploymentSpec{Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "app", Image: "original", ImagePullPolicy: corev1.PullNever}}}}}}
	s := &api.DevelopmentSession{Spec: api.SessionSpec{Container: "app", Image: "registry/dev:2", ImagePullPolicy: "Always", RunAsUser: 1000, RunAsGroup: 1000, Start: api.Start{Command: []string{"run"}}, Directories: []api.Directory{{Name: "src", ImagePath: "/src", MountPath: "/src"}}}}
	p, err := Plan(s, d, "custom/tools:2")
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range []corev1.Container{p.Spec.Containers[0], p.Spec.InitContainers[1]} {
		if c.Image != "registry/dev:2" || c.ImagePullPolicy != corev1.PullAlways {
			t.Fatalf("wrong live/seed image: %+v", c)
		}
	}
	if d.Spec.Template.Spec.Containers[0].Image != "original" {
		t.Fatal("baseline image changed")
	}
	if p.Spec.InitContainers[0].Image != "custom/tools:2" || p.Spec.Containers[1].Image != "custom/tools:2" {
		t.Fatal("tools override lost")
	}
}

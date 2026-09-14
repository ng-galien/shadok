package session

import (
	"encoding/json"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"path"
	api "shadok.org/operator/api/v1alpha1"
	"shadok.org/operator/internal/provision"
	"shadok.org/operator/internal/syncer"
	"strings"
)

func ptr[T any](v T) *T { return &v }
func overlaps(a, b string) bool {
	return a == b || strings.HasPrefix(a, b+"/") || strings.HasPrefix(b, a+"/")
}
func validPath(p string) bool { return strings.HasPrefix(p, "/") && path.Clean(p) == p && p != "/" }
func Plan(s *api.DevelopmentSession, d *appsv1.Deployment, image string) (*corev1.Pod, error) {
	var err error
	d, err = patchTemplate(s, d)
	if err != nil {
		return nil, err
	}

	if len(s.Spec.Directories) == 0 || len(s.Spec.Start.Command) == 0 {
		return nil, fmt.Errorf("directories and live command are required")
	}
	if s.Spec.RunAsUser < 1 || s.Spec.RunAsGroup < 1 {
		return nil, fmt.Errorf("explicit non-root runAsUser/runAsGroup required for shared volumes")
	}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: fmt.Sprintf("%s-dev-%d", s.Name, s.Generation), Namespace: s.Namespace, Labels: map[string]string{"shadok.org/session": s.Name}, Annotations: map[string]string{}}, Spec: *d.Spec.Template.Spec.DeepCopy()}
	for k, v := range d.Spec.Template.Labels {
		pod.Labels[k] = v
	}
	pod.Labels["shadok.org/live-deployment"] = string(d.UID)
	pod.Labels["shadok.org/session"] = string(s.UID)
	// Keep the Deployment's routing labels; its template is transformed in-place.
	for k, v := range d.Spec.Template.Annotations {
		pod.Annotations[k] = v
	}
	target := -1
	for i, c := range pod.Spec.Containers {
		if c.Name == s.Spec.Container {
			target = i
		}
		if strings.HasPrefix(c.Name, "shadok-") {
			return nil, fmt.Errorf("reserved container name")
		}
		for _, port := range c.Ports {
			if port.HostPort != 0 {
				return nil, fmt.Errorf("hostPort unsupported for live rollout")
			}
		}
	}
	if target < 0 {
		return nil, fmt.Errorf("container %q not found", s.Spec.Container)
	}
	for _, c := range pod.Spec.InitContainers {
		if strings.HasPrefix(c.Name, "shadok-") {
			return nil, fmt.Errorf("reserved init name")
		}
	}
	for _, v := range pod.Spec.Volumes {
		if strings.HasPrefix(v.Name, "shadok-") {
			return nil, fmt.Errorf("reserved volume name")
		}
	}
	if pod.Spec.HostNetwork || pod.Spec.HostPID || pod.Spec.HostIPC {
		return nil, fmt.Errorf("host namespaces unsupported for live mode")
	}
	app := &pod.Spec.Containers[target]
	if s.Spec.Image != "" {
		app.Image = s.Spec.Image
	}
	if s.Spec.ImagePullPolicy != "" {
		app.ImagePullPolicy = corev1.PullPolicy(s.Spec.ImagePullPolicy)
	}
	// Do not silently alter an explicit source security identity.
	for _, sc := range []*corev1.SecurityContext{app.SecurityContext} {
		if sc != nil {
			if sc.RunAsUser != nil && *sc.RunAsUser != s.Spec.RunAsUser {
				return nil, fmt.Errorf("runAsUser conflicts with baseline")
			}
			if sc.RunAsGroup != nil && *sc.RunAsGroup != s.Spec.RunAsGroup {
				return nil, fmt.Errorf("runAsGroup conflicts with baseline")
			}
		}
	}
	for _, v := range pod.Spec.Volumes {
		if v.PersistentVolumeClaim != nil && (pod.Spec.SecurityContext == nil || pod.Spec.SecurityContext.FSGroup == nil) {
			return nil, fmt.Errorf("PVC requires an existing compatible fsGroup; refusing implicit ownership changes")
		}
	}
	if pod.Spec.SecurityContext == nil {
		pod.Spec.SecurityContext = &corev1.PodSecurityContext{}
	}
	psc := pod.Spec.SecurityContext
	if psc.FSGroup != nil && *psc.FSGroup != s.Spec.RunAsGroup {
		return nil, fmt.Errorf("fsGroup conflicts with baseline")
	}
	if psc.RunAsUser != nil && *psc.RunAsUser != s.Spec.RunAsUser {
		return nil, fmt.Errorf("pod runAsUser conflicts")
	}
	psc.FSGroup = ptr(s.Spec.RunAsGroup)
	if app.SecurityContext == nil {
		app.SecurityContext = &corev1.SecurityContext{}
	}
	app.SecurityContext.RunAsUser = ptr(s.Spec.RunAsUser)
	app.SecurityContext.RunAsGroup = ptr(s.Spec.RunAsGroup)
	toolSC := &corev1.SecurityContext{RunAsUser: ptr(s.Spec.RunAsUser), RunAsGroup: ptr(s.Spec.RunAsGroup), RunAsNonRoot: ptr(true), AllowPrivilegeEscalation: ptr(false), Capabilities: &corev1.Capabilities{Drop: []corev1.Capability{"ALL"}}}
	resources := corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("10m"), corev1.ResourceMemory: resource.MustParse("32Mi")}, Limits: corev1.ResourceList{corev1.ResourceMemory: resource.MustParse("256Mi")}}
	pod.Spec.Volumes = append(pod.Spec.Volumes, corev1.Volume{Name: "shadok-tools", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}})
	install := corev1.Container{Name: "shadok-install", Image: image, Command: []string{"/shadok", "install", "/tools/shadok"}, VolumeMounts: []corev1.VolumeMount{{Name: "shadok-tools", MountPath: "/tools"}}, SecurityContext: toolSC, Resources: resources}
	seed := corev1.Container{Name: "shadok-seed", Image: app.Image, ImagePullPolicy: app.ImagePullPolicy, Command: []string{"/shadok-tools/shadok", "seed"}, VolumeMounts: []corev1.VolumeMount{{Name: "shadok-tools", MountPath: "/shadok-tools", ReadOnly: true}}, SecurityContext: toolSC, Resources: resources}
	receiver := corev1.Container{Name: "shadok-sync", Image: image, Command: []string{"/shadok", "receive"}, Args: []string{"--listen", "0.0.0.0:7777"}, SecurityContext: toolSC, Resources: resources}
	receiver.Env = []corev1.EnvVar{{Name: "SHADOK_POD_UID", ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.uid"}}}}
	names := map[string]bool{}
	roots := map[string]string{}
	seedRoots := []syncer.Root{}
	for i, v := range s.Spec.Directories {
		if !syncer.ValidMount(v.Name) || names[v.Name] || (v.ImagePath != "" && !validPath(v.ImagePath)) || !validPath(v.MountPath) {
			return nil, fmt.Errorf("invalid directory %q", v.Name)
		}
		names[v.Name] = true
		if v.ImagePath != "" && (overlaps(v.ImagePath, "/shadok-tools") || overlaps(v.ImagePath, "/shadok-seed")) {
			return nil, fmt.Errorf("image path collides with seed mounts")
		}
		for _, old := range app.VolumeMounts {
			if overlaps(v.MountPath, old.MountPath) {
				return nil, fmt.Errorf("live mount %s collides with existing %s", v.MountPath, old.MountPath)
			}
		}
		for _, prev := range s.Spec.Directories[:i] {
			if overlaps(v.MountPath, prev.MountPath) {
				return nil, fmt.Errorf("overlapping live mounts")
			}
		}
		vol := "shadok-live-" + v.Name
		pod.Spec.Volumes = append(pod.Spec.Volumes, corev1.Volume{Name: vol, VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{SizeLimit: ptr(resource.MustParse("1Gi"))}}})
		app.VolumeMounts = append(app.VolumeMounts, corev1.VolumeMount{Name: vol, MountPath: v.MountPath})
		receiver.VolumeMounts = append(receiver.VolumeMounts, corev1.VolumeMount{Name: vol, MountPath: "/live/" + v.Name})
		roots[v.Name] = "/live/" + v.Name
		if v.ImagePath != "" {
			seed.VolumeMounts = append(seed.VolumeMounts, corev1.VolumeMount{Name: vol, MountPath: "/shadok-seed/" + v.Name})
			seedRoots = append(seedRoots, syncer.Root{Mount: v.Name, Path: v.ImagePath})
		}
	}
	raw, _ := json.Marshal(roots)
	receiver.Args = append(receiver.Args, "--roots", string(raw))
	raw, _ = json.Marshal(seedRoots)
	seed.Args = []string{"--roots", string(raw)}
	app.Command = append([]string{}, s.Spec.Start.Command...)
	app.Args = append([]string{}, s.Spec.Start.Args...)
	if s.Spec.Start.WorkingDir != "" {
		app.WorkingDir = s.Spec.Start.WorkingDir
	}
	initializers := []corev1.Container{install, seed}
	if len(seedRoots) == 0 {
		initializers = []corev1.Container{install}
	}
	volumeNames := map[string]bool{}
	var files []provision.File
	prepare := corev1.Container{Name: "shadok-prepare-files", Image: image, Command: []string{"/shadok", "prepare-files"}, SecurityContext: toolSC.DeepCopy(), Resources: *resources.DeepCopy()}
	for _, v := range s.Spec.Volumes {
		if !syncer.ValidMount(v.Name) || len(v.Name) > 49 || volumeNames[v.Name] || !validPath(v.MountPath) {
			return nil, fmt.Errorf("invalid additional volume %q", v.Name)
		}
		volumeNames[v.Name] = true
		for _, existing := range app.VolumeMounts {
			if overlaps(v.MountPath, existing.MountPath) {
				return nil, fmt.Errorf("volume %s collides with mount %s", v.Name, existing.MountPath)
			}
		}
		vol := corev1.Volume{Name: "shadok-extra-" + v.Name}
		sources := 0
		if v.PersistentVolumeClaim != nil {
			sources++
			if v.PersistentVolumeClaim.ClaimName == "" {
				return nil, fmt.Errorf("volume %s requires claimName", v.Name)
			}
			vol.PersistentVolumeClaim = v.PersistentVolumeClaim.DeepCopy()
		}
		if v.ConfigMap != nil {
			sources++
			vol.ConfigMap = v.ConfigMap.DeepCopy()
		}
		if v.Secret != nil {
			sources++
			vol.Secret = v.Secret.DeepCopy()
		}
		if len(v.Files) > 0 {
			sources++
			vol.EmptyDir = &corev1.EmptyDirVolumeSource{SizeLimit: ptr(resource.MustParse("1Gi"))}
			directory := "/resources/" + v.Name
			prepare.VolumeMounts = append(prepare.VolumeMounts, corev1.VolumeMount{Name: vol.Name, MountPath: directory})
			seen := map[string]bool{}
			for _, f := range v.Files {
				file := provision.File{Directory: directory, Path: f.Path, URL: f.URL, SHA256: f.SHA256}
				if err := provision.Validate(file); err != nil {
					return nil, err
				}
				if seen[f.Path] {
					return nil, fmt.Errorf("duplicate tool file %s", f.Path)
				}
				seen[f.Path] = true
				files = append(files, file)
			}
		}
		if sources != 1 {
			return nil, fmt.Errorf("volume %s requires exactly one source", v.Name)
		}
		pod.Spec.Volumes = append(pod.Spec.Volumes, vol)
		app.VolumeMounts = append(app.VolumeMounts, corev1.VolumeMount{Name: vol.Name, MountPath: v.MountPath, ReadOnly: v.ReadOnly})
	}
	if len(files) > 0 {
		raw, _ := json.Marshal(files)
		prepare.Args = []string{string(raw)}
		initializers = append(initializers, prepare)
	}
	initNames := map[string]bool{}
	for _, step := range s.Spec.Init {
		if !syncer.ValidMount(step.Name) || len(step.Name) > 51 || initNames[step.Name] || strings.TrimSpace(step.Image) == "" || len(step.Command) == 0 {
			return nil, fmt.Errorf("invalid initialization step %q", step.Name)
		}
		if step.WorkingDir != "" && !validPath(step.WorkingDir) {
			return nil, fmt.Errorf("invalid initialization workingDir %q", step.WorkingDir)
		}
		switch step.ImagePullPolicy {
		case "", "Always", "IfNotPresent", "Never":
		default:
			return nil, fmt.Errorf("invalid initialization imagePullPolicy %q", step.ImagePullPolicy)
		}
		initNames[step.Name] = true
		c := corev1.Container{Name: "shadok-init-" + step.Name, Image: step.Image, ImagePullPolicy: corev1.PullPolicy(step.ImagePullPolicy), Command: append([]string{}, step.Command...), Args: append([]string{}, step.Args...), WorkingDir: step.WorkingDir, SecurityContext: toolSC.DeepCopy(), Resources: *resources.DeepCopy()}
		for _, directory := range s.Spec.Directories {
			c.VolumeMounts = append(c.VolumeMounts, corev1.VolumeMount{Name: "shadok-live-" + directory.Name, MountPath: directory.MountPath})
		}
		initializers = append(initializers, c)
	}
	pod.Spec.InitContainers = append(initializers, pod.Spec.InitContainers...)
	pod.Spec.Containers = append(pod.Spec.Containers, receiver)
	return pod, nil
}

package chart

import (
	"encoding/json"
	"io"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/util/yaml"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func render(t *testing.T, values string, fail string, args ...string) []unstructured.Unstructured {
	t.Helper()
	dir := t.TempDir()
	file := filepath.Join(dir, "values.json")
	if err := os.WriteFile(file, []byte(values), 0600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("helm", append([]string{"template", "review", "../../chart", "--namespace", "system", "-f", file}, args...)...)
	cmd.Env = append(os.Environ(), "HELM_CACHE_HOME="+dir, "HELM_CONFIG_HOME="+dir, "HELM_DATA_HOME="+dir)
	b, err := cmd.CombinedOutput()
	if fail != "" {
		if err == nil || !strings.Contains(string(b), fail) {
			t.Fatalf("expected failure %q, got %v: %s", fail, err, b)
		}
		return nil
	}
	if err != nil {
		t.Fatalf("render: %v: %s", err, b)
	}
	dec := yaml.NewYAMLOrJSONDecoder(strings.NewReader(string(b)), 4096)
	var result []unstructured.Unstructured
	for {
		var obj unstructured.Unstructured
		err = dec.Decode(&obj)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		if obj.GetKind() != "" {
			result = append(result, obj)
		}
	}
	return result
}
func find(t *testing.T, all []unstructured.Unstructured, kind, name string) unstructured.Unstructured {
	t.Helper()
	for _, o := range all {
		if o.GetKind() == kind && o.GetName() == name {
			return o
		}
	}
	t.Fatalf("missing %s/%s", kind, name)
	return unstructured.Unstructured{}
}
func TestDefaultRoutingAndLeastPrivilege(t *testing.T) {
	all := render(t, `{}`, "")
	gateway := find(t, all, "Deployment", "review-shadok-gateway")
	svc := find(t, all, "Service", "review-shadok")
	selector, _, _ := unstructured.NestedStringMap(svc.Object, "spec", "selector")
	labels, _, _ := unstructured.NestedStringMap(gateway.Object, "spec", "template", "metadata", "labels")
	for k, v := range selector {
		if labels[k] != v {
			t.Fatalf("service does not route to gateway")
		}
	}
	role := find(t, all, "ClusterRole", "review-shadok-gateway-system")
	b, _ := json.Marshal(role.Object["rules"])
	for _, forbidden := range []string{`"secrets"`, `"patch"`, `"create"`, `"deployments"`, `"pods/exec"`} {
		if strings.Contains(string(b), forbidden) {
			t.Fatalf("gateway privilege: %s", b)
		}
	}
	find(t, all, "Role", "review-shadok-leader")
}
func TestScopedHAAndCustomization(t *testing.T) {
	all := render(t, `{"operator":{"replicas":2,"watchNamespaces":["app-a","app-b"],"image":{"repository":"registry/team/operator","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"pdb":{"enabled":true}},"gateway":{"autoscaling":{"enabled":true},"podAnnotations":{"example.com/reload":"yes"}},"metrics":{"enabled":true,"serviceMonitor":{"enabled":true}},"networkPolicy":{"enabled":true,"apiServerCIDRs":["10.96.0.1/32"]},"ingress":{"enabled":true,"hosts":[{"host":"sync.example.com","paths":[{"path":"/","pathType":"Prefix"}]}]}}`, "", "--api-versions", "monitoring.coreos.com/v1/ServiceMonitor")
	for _, o := range all {
		if o.GetKind() == "ClusterRole" {
			t.Fatal("scoped installation grants cluster permissions")
		}
	}
	find(t, all, "HorizontalPodAutoscaler", "review-shadok-gateway")
	find(t, all, "PodDisruptionBudget", "review-shadok")
	find(t, all, "ServiceMonitor", "review-shadok")
	find(t, all, "NetworkPolicy", "review-shadok-gateway")
	op := find(t, all, "Deployment", "review-shadok")
	c, _, _ := unstructured.NestedSlice(op.Object, "spec", "template", "spec", "containers")
	if c[0].(map[string]interface{})["image"] != "registry/team/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" {
		t.Fatal("digest override lost")
	}
	gateway := find(t, all, "Deployment", "review-shadok-gateway")
	if _, ok, _ := unstructured.NestedFieldNoCopy(gateway.Object, "spec", "replicas"); ok {
		t.Fatal("HPA replicas overridden")
	}
}
func TestInvalidValues(t *testing.T) {
	for _, tc := range []struct{ name, values, want string }{
		{"unknown", `{"operatr":{}}`, "additional properties"},
		{"HA", `{"operator":{"replicas":2,"leaderElection":{"enabled":false}}}`, "requires leaderElection"},
		{"PDB", `{"operator":{"pdb":{"enabled":true,"maxUnavailable":1}}}`, "exactly one"},
		{"network", `{"networkPolicy":{"enabled":true}}`, "apiServerCIDRs"},
		{"monitor", `{"metrics":{"enabled":true,"serviceMonitor":{"enabled":true}}}`, "Prometheus Operator CRD"},
		{"scale", `{"gateway":{"autoscaling":{"enabled":true,"minReplicas":6,"maxReplicas":2}}}`, "exceeds maxReplicas"},
		{"image", `{"operator":{"image":{"digest":"sha256:wrong"}}}`, "digest"},
		{"port", `{"service":{"port":70000}}`, "maximum"},
		{"session", `{"session":{"create":true}}`, "existing Deployment"},
	} {
		t.Run(tc.name, func(t *testing.T) { render(t, tc.values, tc.want) })
	}
}
func TestSessionOnlyCustomImage(t *testing.T) {
	all := render(t, `{"operator":{"enabled":false},"session":{"create":true,"deployment":"app","image":"team/dev:1","imagePullPolicy":"Always","directories":[{"name":"src","imagePath":"/app","mountPath":"/app"}],"start":{"command":["/app/run"]}}}`, "")
	if len(all) != 1 {
		t.Fatalf("unexpected infrastructure: %d", len(all))
	}
	s := all[0]
	v, _, _ := unstructured.NestedString(s.Object, "spec", "image")
	if v != "team/dev:1" {
		t.Fatal("custom image lost")
	}
}

func TestMetadataAndExistingAccounts(t *testing.T) {
	all := render(t, `{"commonLabels":{"example.com/team":"platform","app.kubernetes.io/instance":"cannot-override-selector"},"commonAnnotations":{"example.com/audit":"yes"},"rbac":{"create":false},"serviceAccounts":{"operator":{"create":false,"name":"existing-operator"},"gateway":{"create":false,"name":"existing-gateway"}},"operator":{"podAnnotations":{"checksum/config":"abc"},"extraEnv":[{"name":"EXAMPLE","value":"configured"}]},"gateway":{"tlsSecretName":"custom-tls"}}`, "")
	for _, o := range all {
		if o.GetKind() == "ServiceAccount" || o.GetKind() == "ClusterRole" || o.GetKind() == "Role" {
			t.Fatalf("unexpected managed permissions: %s", o.GetKind())
		}
	}
	op := find(t, all, "Deployment", "review-shadok")
	if op.GetAnnotations()["example.com/audit"] != "yes" {
		t.Fatal("common annotations missing")
	}
	sa, _, _ := unstructured.NestedString(op.Object, "spec", "template", "spec", "serviceAccountName")
	if sa != "existing-operator" {
		t.Fatal("existing account ignored")
	}
	labels, _, _ := unstructured.NestedStringMap(op.Object, "spec", "template", "metadata", "labels")
	if labels["app.kubernetes.io/instance"] != "review-shadok" {
		t.Fatal("selector label overwritten")
	}
	containers, _, _ := unstructured.NestedSlice(op.Object, "spec", "template", "spec", "containers")
	env := containers[0].(map[string]interface{})["env"].([]interface{})
	if env[0].(map[string]interface{})["value"] != "configured" {
		t.Fatal("env override lost")
	}
	gw := find(t, all, "Deployment", "review-shadok-gateway")
	vols, _, _ := unstructured.NestedSlice(gw.Object, "spec", "template", "spec", "volumes")
	if len(vols) != 2 {
		t.Fatal("TLS volume missing")
	}
}
func TestUnsupportedKubernetes(t *testing.T) {
	render(t, `{}`, "kubeVersion", "--kube-version", "1.24.0")
}

func TestKubernetesAPIFloor(t *testing.T) {
	render(t, `{}`, "", "--kube-version", "1.25.0")
}

package session

import (
	"bytes"
	"encoding/json"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/util/strategicpatch"
	api "shadok.org/operator/api/v1alpha1"
	"sigs.k8s.io/yaml"
)

func patchTemplate(s *api.DevelopmentSession, d *appsv1.Deployment) (*appsv1.Deployment, error) {
	if s.Spec.PodTemplatePatch == "" {
		return d, nil
	}
	original, err := json.Marshal(d.Spec.Template)
	if err != nil {
		return nil, err
	}
	patch, err := yaml.YAMLToJSONStrict([]byte(s.Spec.PodTemplatePatch))
	if err != nil {
		return nil, fmt.Errorf("podTemplatePatch: %w", err)
	}
	patched, err := strategicpatch.StrategicMergePatch(original, patch, corev1.PodTemplateSpec{})
	if err != nil {
		return nil, fmt.Errorf("podTemplatePatch: %w", err)
	}
	out := d.DeepCopy()
	var template corev1.PodTemplateSpec
	decoder := json.NewDecoder(bytes.NewReader(patched))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&template); err != nil {
		return nil, fmt.Errorf("podTemplatePatch: %w", err)
	}
	out.Spec.Template = template
	selector, err := metav1.LabelSelectorAsSelector(d.Spec.Selector)
	if err != nil {
		return nil, err
	}
	if !selector.Matches(labels.Set(template.Labels)) {
		return nil, fmt.Errorf("podTemplatePatch removes Deployment routing labels")
	}
	return out, nil
}

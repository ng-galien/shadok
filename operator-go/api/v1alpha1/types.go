// Package v1alpha1 defines the experimental generic development session API.
// +kubebuilder:object:generate=true
// +groupName=shadok.org
package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var GroupVersion = schema.GroupVersion{Group: "shadok.org", Version: "v1alpha1"}
var SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}
var AddToScheme = SchemeBuilder.AddToScheme

type Directory struct {
	// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9-]*$`
	// +kubebuilder:validation:MaxLength=51
	Name      string `json:"name"`
	ImagePath string `json:"imagePath"`
	MountPath string `json:"mountPath"`
}
type Start struct {
	// +kubebuilder:validation:MinItems=1
	Command    []string `json:"command"`
	Args       []string `json:"args,omitempty"`
	WorkingDir string   `json:"workingDir,omitempty"`
}

// InitStep runs after image directories are seeded and before the application starts.
// All declared live directories are mounted at their application mount paths.
type InitStep struct {
	// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9-]*$`
	// +kubebuilder:validation:MaxLength=51
	Name string `json:"name"`
	// +kubebuilder:validation:MinLength=1
	Image string `json:"image"`
	// +kubebuilder:validation:Enum=Always;IfNotPresent;Never
	ImagePullPolicy string `json:"imagePullPolicy,omitempty"`
	// +kubebuilder:validation:MinItems=1
	Command    []string `json:"command"`
	Args       []string `json:"args,omitempty"`
	WorkingDir string   `json:"workingDir,omitempty"`
}

type SessionSpec struct {
	// Enable live transformation of the existing Deployment; false restores its baseline.
	Enabled bool `json:"enabled"`

	// Deployment in the same namespace, transformed in place.
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="deployment is immutable; create a new session to retarget"
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Deployment string `json:"deployment"`
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Container string `json:"container"`
	// Optional live image; the baseline image is restored when disabled.
	Image string `json:"image,omitempty"`
	// +kubebuilder:validation:Enum=Always;IfNotPresent;Never
	ImagePullPolicy string `json:"imagePullPolicy,omitempty"`
	// +kubebuilder:validation:MinItems=1
	// +listType=map
	// +listMapKey=name
	Directories []Directory `json:"directories"`
	Start       Start       `json:"start"`
	// Ordered initialization commands; no framework-specific behavior is inferred.
	// +listType=atomic
	Init []InitStep `json:"init,omitempty"`
	// A session-specific UID/GID for shared emptyDir writes. Must match the baseline runtime.
	// +kubebuilder:validation:Minimum=1
	RunAsUser int64 `json:"runAsUser"`
	// +kubebuilder:validation:Minimum=1
	RunAsGroup int64 `json:"runAsGroup"`
}
type SessionStatus struct {
	BaselineImage      string             `json:"baselineImage,omitempty"`
	ObservedGeneration int64              `json:"observedGeneration,omitempty"`
	Conditions         []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
type DevelopmentSession struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              SessionSpec   `json:"spec"`
	Status            SessionStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type DevelopmentSessionList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []DevelopmentSession `json:"items"`
}

func init() { SchemeBuilder.Register(&DevelopmentSession{}, &DevelopmentSessionList{}) }
